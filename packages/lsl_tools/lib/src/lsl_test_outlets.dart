import 'dart:async';
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';

import 'lsl.dart';

/// A synthetic stream for testing a pipeline, sent in real time: one of
/// signal_core's [SynthPreset]s (by default sine waves, channel n at n ×
/// [frequency], with noise), optionally with simulated dropouts and jitter
/// and a companion marker stream named `<name> markers`.
class LslSignalGenerator {
  final LslOutlet outlet;

  /// The marker stream, if markers are sent.
  final LslOutlet? markerOutlet;
  final SynthSpec spec;
  final SynthRun _run;
  final List<Future<void>> _pending = [];
  int _markersSent = 0;

  LslSignalGenerator._(this.outlet, this.markerOutlet, this.spec, this._run);

  static Future<LslSignalGenerator> start({
    String name = 'Test signal',
    String type = 'EEG',
    int channels = 8,
    double rate = 250,
    double frequency = 10,
    double amplitude = 50,
    double noise = 5,
    SynthPreset preset = SynthPreset.sines,
    double lineFrequency = 50,
    int seed = 0,
    MarkerSchedule? markers,
    Impairments impairments = Impairments.none,
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    final spec = SynthSpec(
      preset: preset,
      channels: channels,
      rate: rate,
      frequency: frequency,
      amplitude: amplitude,
      noise: noise,
      lineFrequency: lineFrequency,
      seed: seed,
    );
    final generator = spec.generator();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: type,
        channelCount: channels,
        rate: rate,
        sourceId: 'test:$name:$stamp',
        channels: [
          for (var c = 0; c < channels; c++)
            LSLChannel(
              generator.labels[c],
              unit: generator.units[c],
              type: type,
            ),
        ],
      ),
      options,
    );
    LslOutlet? markerOutlet;
    if (markers != null) {
      markerOutlet = await lsl.createOutlet(
        LslOutletSpec(
          name: '$name markers',
          type: 'Markers',
          channelCount: 1,
          rate: 0,
          format: LSLChannelFormat.string,
          sourceId: 'test:$name:markers:$stamp',
        ),
        options,
      );
    }
    late final LslSignalGenerator g;
    final run = SynthRun(
      generator,
      clock: lsl.clock,
      impairments: impairments,
      markers: markers,
      onChunk: (c) => g._push(c),
      onMarkers: markerOutlet == null ? null : (m) => g._mark(m),
    );
    return g = LslSignalGenerator._(outlet, markerOutlet, spec, run);
  }

  String get name => outlet.spec.name;
  double get rate => spec.rate;

  /// Samples sent, and lost in simulated dropouts.
  int get sent => _run.sent;
  int get lost => _run.lost;
  int get markersSent => _markersSent;

  void _track(Future<void> f) {
    _pending.add(f);
    f.whenComplete(() => _pending.remove(f));
  }

  void _push(SynthChunk c) =>
      _track(outlet.push(Float32List.fromList(c.values), c.times));

  void _mark(List<SynthMarker> markers) {
    _markersSent += markers.length;
    _track(
      markerOutlet!.pushStrings(
        [for (final m in markers) m.text],
        [for (final m in markers) m.time],
      ),
    );
  }

  Future<void> close() async {
    _run.stop();
    await Future.wait(List.of(_pending));
    await outlet.close();
    await markerOutlet?.close();
  }
}

/// A marker stream the user sends text on, e.g. to annotate a session.
class LslMarkerSender {
  final LslOutlet outlet;
  int sent = 0;

  LslMarkerSender._(this.outlet);

  static Future<LslMarkerSender> start({
    String name = 'Viewer markers',
    LslOutletOptions options = const LslOutletOptions(),
  }) async => LslMarkerSender._(
    await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: 'Markers',
        channelCount: 1,
        rate: 0,
        format: LSLChannelFormat.string,
        sourceId: 'markers:$name:${DateTime.now().microsecondsSinceEpoch}',
      ),
      options,
    ),
  );

  String get name => outlet.spec.name;

  /// Send [text], stamped now.
  Future<void> send(String text) async {
    await outlet.pushStrings([text], [lsl.clock()]);
    sent++;
  }

  Future<void> close() => outlet.close();
}
