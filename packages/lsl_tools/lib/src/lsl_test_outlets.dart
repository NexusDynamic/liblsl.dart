import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'lsl.dart';

/// A synthetic stream for testing a pipeline: a sine wave per channel
/// (channel c at [frequency] × (c + 1) Hz, [amplitude] peak) plus noise,
/// sent in real time.
class LslSignalGenerator {
  final LslOutlet outlet;
  final double rate;
  final double frequency;
  final double amplitude;
  final double noise;
  final _rng = math.Random();
  late final Timer _timer;
  late double _next;
  int _sent = 0;

  LslSignalGenerator._(
    this.outlet,
    this.rate,
    this.frequency,
    this.amplitude,
    this.noise,
  ) {
    _next = lsl.clock();
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  static Future<LslSignalGenerator> start({
    String name = 'Test signal',
    String type = 'EEG',
    int channels = 8,
    double rate = 250,
    double frequency = 10,
    double amplitude = 50,
    double noise = 5,
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: type,
        channelCount: channels,
        rate: rate,
        sourceId: 'test:$name:${DateTime.now().microsecondsSinceEpoch}',
        channels: [
          for (var c = 0; c < channels; c++)
            LslChannel('ch${c + 1}', unit: 'microvolts', type: type),
        ],
      ),
      options,
    );
    return LslSignalGenerator._(outlet, rate, frequency, amplitude, noise);
  }

  String get name => outlet.spec.name;
  int get sent => _sent;

  void _tick() {
    final now = lsl.clock();
    final n = ((now - _next) * rate).floor();
    if (n <= 0) return;
    final ch = outlet.spec.channelCount;
    final values = Float32List(n * ch);
    final times = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = _next + i / rate;
      times[i] = t;
      for (var c = 0; c < ch; c++) {
        values[i * ch + c] =
            amplitude * math.sin(2 * math.pi * frequency * (c + 1) * t) +
            noise * (_rng.nextDouble() * 2 - 1);
      }
    }
    _next += n / rate;
    _sent += n;
    outlet.push(values, times);
  }

  Future<void> close() async {
    _timer.cancel();
    await outlet.close();
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
        format: LslFormat.string,
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
