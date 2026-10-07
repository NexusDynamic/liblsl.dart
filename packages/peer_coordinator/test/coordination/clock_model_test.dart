/// The drift fit, the hop arithmetic and the timestamp smoother, pinned with
/// synthetic data built from a known ground truth.
library;

import 'dart:math';

import 'package:peer_coordinator/coordination.dart';
import 'package:peer_coordinator/data.dart';
import 'package:test/test.dart';

void main() {
  group('ClockModel', () {
    /// Estimates every 2 s of a clock [offset] ahead at remote time 0 and
    /// drifting by [drift], each off by up to [noise] seconds.
    ClockModel fitted({
      required double offset,
      required double drift,
      double noise = 0,
      int count = 30,
    }) {
      final random = Random(1);
      final model = ClockModel();
      for (var i = 0; i < count; i++) {
        final remote = 1000.0 + i * 2;
        model.add(
          ClockOffsetEstimate(
            offset:
                offset + drift * remote + (random.nextDouble() - 0.5) * noise,
            uncertainty: 0.002,
            remoteTime: remote,
            sampledAt: 0,
          ),
        );
      }
      return model;
    }

    test('is not ready before the first estimate', () {
      expect(ClockModel().ready, isFalse);
    });

    test('recovers offset and drift from noisy estimates', () {
      final model = fitted(offset: 1234.5, drift: 50e-6, noise: 200e-6);
      expect(model.drift, closeTo(50e-6, 5e-6));
      // Between and just past the estimates.
      for (final t in [1030.0, 1058.0, 1061.0]) {
        expect(model.offsetAt(t), closeTo(1234.5 + 50e-6 * t, 100e-6));
      }
      expect(model.uncertainty, 0.002);
    });

    test('does not step between estimates', () {
      final model = fitted(offset: -7, drift: 20e-6);
      final a = model.offsetAt(1050);
      final b = model.offsetAt(1050.001);
      expect((b - a).abs(), lessThan(1e-7));
    });

    test('fits no slope through a few seconds of estimates', () {
      final model = fitted(offset: 3, drift: 0, noise: 1e-3, count: 3);
      expect(model.drift, 0);
      expect(model.offsetAt(1002), closeTo(3, 1e-3));
    });

    test('forgets estimates older than the window', () {
      final model = ClockModel(window: 10);
      for (var i = 0; i < 20; i++) {
        model.add(
          ClockOffsetEstimate(
            // A step at i == 10, as after a clock reset.
            offset: i < 10 ? 5 : 9,
            uncertainty: 0.001,
            remoteTime: i * 2.0,
            sampledAt: 0,
          ),
        );
      }
      expect(model.offsetAt(38), closeTo(9, 1e-9));
    });
  });

  group('ClockHop and ClockChain', () {
    const hop = ClockHop(
      node: 'b',
      via: 'bridge',
      offset: 100,
      drift: 50e-6,
      at: 2000,
      uncertainty: 0.004,
    );

    test('maps a time with offset and drift', () {
      expect(hop.map(2000), closeTo(2100, 1e-12));
      expect(hop.map(3000), closeTo(3100.05, 1e-9));
    });

    test('the inverse undoes the hop', () {
      final back = hop.inverse(node: 'a');
      for (final t in [0.0, 2000.0, 54321.0]) {
        expect(back.map(hop.map(t)), closeTo(t, 1e-8));
      }
      expect(back.uncertainty, hop.uncertainty);
      expect(back.node, 'a');
    });

    test('a chain adds offsets and bounds, and keeps the last latency', () {
      final chain = ClockChain.empty
          .then(
            const ClockHop(
              node: 'a',
              via: 'lsl',
              offset: 10,
              uncertainty: 0.0002,
              latency: 0.004,
            ),
          )
          .then(hop);
      expect(chain.offsetAt(1990), closeTo(110, 1e-9));
      expect(chain.uncertainty, closeTo(0.0042, 1e-12));
      expect(chain.drift, closeTo(50e-6, 1e-12));
      expect(chain.latency, 0.004);
      expect(ClockChain.empty.map(5), 5);
    });

    test('time held at a node is per hop, added up, and kept apart from '
        'the latency', () {
      const waited = ClockHop(
        node: 'a',
        via: 'lsl',
        offset: 0,
        latency: 0.004,
        held: 0.05,
      );
      expect(ClockChain.empty.then(hop).held, isNull);
      final chain = ClockChain.empty
          .then(waited)
          .then(hop.withLatency(0.006, 0.001, held: 0.01));
      expect(chain.held, closeTo(0.06, 1e-12));
      expect(chain.latency, 0.006);

      // On the wire only when measured, so an older peer sees what it did.
      expect(hop.toJson().containsKey('held'), isFalse);
      final again = ClockChain.fromJson(chain.toJson());
      expect(again.hops.first.held, 0.05);
      expect(again.hops.last.held, 0.01);
      // Latency measured where it arrived replaces the latency, not this.
      expect(waited.withLatency(0.1, null).held, 0.05);
      expect(waited.inverse(node: 'o').held, isNull);
    });

    test('survives the wire, dropping what is not a finite number', () {
      final json = ClockChain.empty.then(hop).toJson();
      final again = ClockChain.fromJson(json);
      expect(again.hops.single.map(3000), hop.map(3000));
      expect(again.hops.single.latency, isNull);

      final hostile = ClockChain.fromJson([
        {'node': 'x', 'via': 'bridge', 'offset': 'NaN', 'drift': double.nan},
        'not a hop',
      ]);
      expect(hostile.hops.single.offset, 0);
      expect(hostile.hops.single.drift, 0);
      expect(ClockChain.fromJson('nonsense').hops, isEmpty);
      expect(
        ClockChain.fromJson(List.filled(100, hop.toJson())).hops.length,
        ClockChain.maxHops,
      );
    });
  });

  group('TimestampSmoother', () {
    test('removes stamping jitter and keeps the rate', () {
      final random = Random(2);
      const rate = 250.0, start = 1e6;
      final smoother = TimestampSmoother(rate);
      var rawError = 0.0, smoothError = 0.0;
      const n = 5000;
      for (var i = 0; i < n; i++) {
        final truth = start + i / rate;
        final raw = truth + (random.nextDouble() - 0.5) * 4e-3;
        final smooth = smoother.smooth(raw);
        if (i >= n ~/ 2) {
          rawError += (raw - truth).abs();
          smoothError += (smooth - truth).abs();
        }
      }
      expect(smoothError, lessThan(rawError / 10));
    });

    test('follows a rate that is not the nominal one', () {
      // Nominally 100 Hz, really 100.5 Hz.
      final smoother = TimestampSmoother(100);
      late double out;
      for (var i = 0; i < 20000; i++) {
        out = smoother.smooth(50 + i / 100.5);
      }
      expect(out, closeTo(50 + 19999 / 100.5, 1e-4));
    });

    test('monotonize never goes backwards', () {
      final smoother = TimestampSmoother(10, monotonize: true);
      var last = double.negativeInfinity;
      for (final t in [0.0, 0.1, 0.2, 0.05, 0.06, 0.5]) {
        final out = smoother.smooth(t);
        expect(out, greaterThanOrEqualTo(last));
        last = out;
      }
    });
  });

  group('LatencyWindow', () {
    test('reports mean and spread of what it holds', () {
      final window = LatencyWindow(4);
      expect(window.mean, isNull);
      for (final v in [9.0, 9.0, 0.010, 0.020, 0.010, 0.020]) {
        window.add(v);
      }
      window.add(double.nan);
      expect(window.mean, closeTo(0.015, 1e-12));
      expect(window.jitter, closeTo(0.005, 1e-12));
    });
  });
}
