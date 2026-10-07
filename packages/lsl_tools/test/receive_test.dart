@Tags(['lsl'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:lsl_tools/lsl_tools.dart';
import 'package:test/test.dart';

/// [receiveChunks]: samples as they arrive where the inlet can, on a timer
/// where it cannot or is told not to, and never stopping without a word.
void main() {
  final id = DateTime.now().microsecondsSinceEpoch;
  var streams = 0;

  /// An outlet sending the sample number on one channel, 100 a second, and
  /// an inlet on it.
  Future<LslInlet> counting({double rate = 100}) async {
    final name = 'receive_${id}_${streams++}';
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: 'EEG',
        channelCount: 1,
        rate: rate,
        sourceId: name,
      ),
      const LslOutletOptions(),
    );
    final discovery = lsl.discover();
    LslStreamDescription? found;
    for (var i = 0; i < 100 && found == null; i++) {
      final s = (await discovery.streams()).where((s) => s.name == name);
      if (s.isNotEmpty) found = s.first;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final inlet = await lsl.openInlet(
      found!,
      const LslInletOptions(dejitter: false),
    );
    var n = 0;
    final sender = Timer.periodic(const Duration(milliseconds: 10), (_) {
      outlet.push(
        Float32List.fromList([(n++).toDouble()]),
        Float64List.fromList([lsl.clock()]),
      );
    });
    addTearDown(() async {
      sender.cancel();
      await inlet.close();
      await outlet.close();
      discovery.close();
    });
    return inlet;
  }

  Future<void> until(bool Function() condition, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// That [values] go up by one, i.e. nothing was lost or repeated.
  void expectUnbroken(List<double> values) {
    for (var i = 1; i < values.length; i++) {
      expect(values[i], values[i - 1] + 1, reason: 'at sample $i');
    }
  }

  test('samples come as they arrive, with when they did', () async {
    final inlet = await counting();
    expect(inlet, isA<LslArrivals>());
    final statuses = <LslReceiveStatus>[];
    final values = <double>[];
    final waits = <double>[];
    final sub =
        receiveChunks(
          inlet,
          const LslInletOptions(),
          onStatus: statuses.add,
        ).listen((c) {
          values.addAll(c.values!);
          waits.add(c.received! - c.times.first);
        });
    await until(() => values.length > 100, 'samples should arrive');
    await sub.cancel();

    expectUnbroken(values);
    expect(statuses.single.eventDriven, isTrue);
    expect(statuses.single.healthy, isTrue);
    // Same computer, same clock: the first sample of a chunk was received
    // moments after it was stamped, however long the chunk took to come.
    waits.sort();
    expect(waits[waits.length ~/ 2], inInclusiveRange(0, 0.005));
  });

  test('turned off, they are collected on a timer', () async {
    final inlet = await counting();
    final statuses = <LslReceiveStatus>[];
    final values = <double>[];
    var chunks = 0;
    final sub =
        receiveChunks(
          inlet,
          const LslInletOptions(eventDriven: false, pullIntervalMs: 100),
          onStatus: statuses.add,
        ).listen((c) {
          values.addAll(c.values!);
          chunks++;
        });
    await until(() => values.length > 100, 'samples should arrive');
    await sub.cancel();

    expectUnbroken(values);
    expect(statuses.single.eventDriven, isFalse);
    // About ten samples to a collection, not one or two.
    expect(values.length / chunks, greaterThan(4));
  });

  test('a listener that dies is reported and restarted', () async {
    final inlet = await counting();
    final statuses = <LslReceiveStatus>[];
    final values = <double>[];
    final sub = receiveChunks(
      inlet,
      const LslInletOptions(),
      onStatus: statuses.add,
      debugListenerFaults: 1,
    ).listen((c) => values.addAll(c.values!));
    await until(
      () => statuses.length == 3,
      'it should have failed and recovered',
    );
    final before = values.length;
    await until(() => values.length > before + 50, 'samples should go on');
    await sub.cancel();

    final failed = statuses[1];
    expect(failed.healthy, isFalse);
    expect(failed.failures, 1);
    expect(failed.fellBack, isFalse);
    expect(failed.cause, contains('debugFailAfter'));
    expect(failed.note, contains('restarted 1×'));
    expect(statuses[2].healthy, isTrue);
    expect(statuses[2].eventDriven, isTrue);
    // What came while nothing listened was waiting in the inlet.
    expectUnbroken(values);
  });

  test('one that keeps dying is replaced by the timer', () async {
    final inlet = await counting();
    final statuses = <LslReceiveStatus>[];
    final values = <double>[];
    final sub = receiveChunks(
      inlet,
      const LslInletOptions(),
      onStatus: statuses.add,
      debugListenerFaults: receiveFallbackAfter,
    ).listen((c) => values.addAll(c.values!));
    await until(
      () => statuses.isNotEmpty && statuses.last.fellBack,
      'it should have given up listening',
    );
    final before = values.length;
    await until(() => values.length > before + 50, 'samples should go on');
    await sub.cancel();

    expect([for (final s in statuses) s.failures], [0, 1, 2, 3]);
    expect(statuses.last.eventDriven, isFalse);
    expect(statuses.last.healthy, isFalse);
    expect(statuses.last.note, contains('on a timer after 3 failures'));
    expectUnbroken(values);
  });

  test('options remember the choice, and default to arriving', () {
    expect(const LslInletOptions().eventDriven, isTrue);
    expect(LslInletOptions.fromJson(const {}).eventDriven, isTrue);
    final off = const LslInletOptions().copyWith(eventDriven: false);
    expect(LslInletOptions.fromJson(off.toJson()).eventDriven, isFalse);
  });
}
