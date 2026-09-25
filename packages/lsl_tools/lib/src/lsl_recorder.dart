import 'dart:async';
import 'dart:math' as math;

import 'package:xdf/xdf.dart';

import 'lsl.dart';

/// One stream being recorded.
class LslRecordedStream {
  /// Its id in the file.
  final int id;
  final LslInlet inlet;

  /// Samples written so far.
  int samples = 0;

  /// Clock offsets written so far.
  int offsets = 0;

  /// Why receiving stopped, if it did.
  String? error;

  LslRecordedStream(this.id, this.inlet);

  LslStreamDescription get stream => inlet.stream;
}

/// Records LSL streams to an XDF file, as LabRecorder does: raw time stamps
/// (no clock synchronisation or dejittering; readers do that from the
/// clock offsets), each stream's full info as its header, a clock offset
/// per stream every [offsetInterval], a boundary chunk every
/// [boundaryInterval], and footers when stopped.
class LslRecorder {
  final XdfWriter _writer;
  final List<LslRecordedStream> streams;

  /// Where the file goes, for display.
  final String where;

  final DateTime started = DateTime.now();
  final Duration pullInterval;
  final Duration offsetInterval;
  final Duration boundaryInterval;

  bool _stopped = false;
  late final Future<void> _loop;

  LslRecorder._(
    this._writer,
    this.streams,
    this.where,
    this.pullInterval,
    this.offsetInterval,
    this.boundaryInterval,
  ) {
    _loop = _run();
  }

  /// How recording inlets receive: everything, with raw time stamps.
  static const inletOptions = LslInletOptions(
    bufferS: 360,
    clockSync: false,
    dejitter: false,
  );

  /// Open an inlet for each of [streams] and record them to [sink].
  static Future<LslRecorder> start(
    List<LslStreamDescription> streams,
    Sink<List<int>> sink, {
    String where = '',
    Duration pullInterval = const Duration(milliseconds: 100),
    Duration offsetInterval = const Duration(seconds: 5),
    Duration boundaryInterval = const Duration(seconds: 10),
  }) async {
    final inlets = <LslInlet>[];
    try {
      for (final s in streams) {
        inlets.add(await lsl.openInlet(s, inletOptions));
      }
    } catch (_) {
      for (final i in inlets) {
        await i.close();
      }
      rethrow;
    }
    final now = DateTime.now().toUtc();
    final writer = XdfWriter(sink, header: {'datetime': now.toIso8601String()});
    final recorded = <LslRecordedStream>[];
    for (final (k, inlet) in inlets.indexed) {
      final id = k + 1;
      final xml = inlet.fullXml.isNotEmpty ? inlet.fullXml : inlet.stream.xml;
      writer.addStream(id, XdfStreamInfo.parse(xml));
      recorded.add(LslRecordedStream(id, inlet));
    }
    return LslRecorder._(
      writer,
      recorded,
      where,
      pullInterval,
      offsetInterval,
      boundaryInterval,
    );
  }

  bool get stopped => _stopped;

  Duration get elapsed => DateTime.now().difference(started);

  int get sampleCount => streams.fold(0, (n, s) => n + s.samples);

  Future<void> _run() async {
    final sinceOffsets = Stopwatch();
    final sinceBoundary = Stopwatch()..start();
    var first = true;
    while (!_stopped) {
      if (first || sinceOffsets.elapsed >= offsetInterval) {
        first = false;
        sinceOffsets
          ..reset()
          ..start();
        await _offsets();
      }
      await _pull();
      if (sinceBoundary.elapsed >= boundaryInterval) {
        _writer.writeBoundary();
        sinceBoundary.reset();
      }
      await Future<void>.delayed(pullInterval);
    }
  }

  Future<void> _offsets() async {
    for (final s in streams) {
      if (s.error != null) continue;
      try {
        final offset = await s.inlet.timeCorrection();
        _writer.writeClockOffset(s.id, lsl.clock(), offset);
        s.offsets++;
      } catch (_) {
        // No offset now (e.g. the sender is gone for a moment).
      }
    }
  }

  Future<void> _pull() async {
    for (final s in streams) {
      if (s.error != null) continue;
      try {
        while (true) {
          final max = math.max(256, (s.stream.rate * 2).ceil());
          final c = await s.inlet.pull(max);
          if (c.length == 0) break;
          if (c.strings != null) {
            _writer.writeStrings(s.id, c.times, c.strings!);
          } else {
            _writer.writeSamples(s.id, c.times, c.values!);
          }
          s.samples += c.length;
          if (c.length < max) break;
        }
      } catch (e) {
        s.error = '$e';
      }
    }
  }

  /// Collect what is left, write the footers and close the file.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _loop;
    await _pull();
    await _offsets();
    await _writer.close();
    for (final s in streams) {
      await s.inlet.close();
    }
  }
}
