import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer/signal_viewer.dart';

import 'line_parser.dart';

/// Numbers read line by line from a serial port, shown as a live stream.
///
/// The sampling rate is given, or measured over the first
/// [measureFor]; samples are placed on its grid by when they arrive, and a
/// gap (samples lost) is filled by interpolation, as for LSL streams.
class SerialStreamSession extends SourceSession implements LiveData {
  final String name;
  final String portName;
  final SerialTransport transport;
  final String type;

  /// Nominal rate in Hz, or null to measure it.
  final double? givenRate;
  final Duration measureFor;

  final _parser = SerialLineParser();
  final _changes = Changes();
  final Stopwatch _clock = Stopwatch()..start();
  late final StreamSubscription<Uint8List> _sub;

  List<String>? _labels;
  int? _channels;
  RegularRing? _ring;
  StreamInfo? _info;

  /// Samples (and their arrival times) while the rate is measured.
  final List<(double, Float64List)> _early = [];

  double _anchor = 0;
  int received = 0;
  int skipped = 0;
  bool _closed = false;
  String? error;

  SerialStreamSession._(
    this.name,
    this.portName,
    this.transport,
    this.type,
    this.givenRate,
    this.measureFor,
  ) {
    _sub = transport.input.listen(
      _onBytes,
      onError: (Object e) {
        error = '$e';
        notifyListeners();
      },
      onDone: () {
        error ??= 'The port closed';
        notifyListeners();
      },
    );
  }

  /// Open [port] at [baudRate] and read it.
  static Future<SerialStreamSession> open(
    SerialPortProvider provider,
    SerialPortInfo port, {
    required String name,
    int? baudRate,
    double? rate,
    String type = '',
    Duration measureFor = const Duration(seconds: 2),
  }) async {
    final transport = await provider.open(port, baudRate: baudRate);
    return SerialStreamSession._(
      name,
      port.description.isEmpty ? port.id : port.description,
      transport,
      type,
      rate != null && rate > 0 ? rate : null,
      measureFor,
    );
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  /// The rate samples are placed at, once known.
  double? get rate => _ring?.rate;

  void _onBytes(Uint8List bytes) {
    for (final line in _parser.add(bytes)) {
      if (line is SerialLabels) {
        _labels ??= line.labels;
      }
      if (line is SerialValues) _sample(line.values);
    }
  }

  void _sample(Float64List v) {
    final n = _channels ??= v.length;
    if (v.length != n) {
      skipped++;
      return;
    }
    received++;
    final t = _now;
    final ring = _ring;
    if (ring == null) {
      _early.add((t, v));
      final rate = givenRate ?? _measured();
      if (rate != null) _start(rate);
      return;
    }
    _place(ring, t, v);
    _changes.ping();
  }

  /// The rate measured from the samples so far, once [measureFor] passed.
  double? _measured() {
    if (_early.length < 3) return null;
    final span = _early.last.$1 - _early.first.$1;
    if (span < measureFor.inMicroseconds / 1e6) return null;
    final r = (_early.length - 1) / span;
    // A round number when close to one (e.g. 250 Hz, not 249.7).
    for (final nice in [
      1,
      2,
      5,
      10,
      20,
      25,
      50,
      100,
      125,
      200,
      250,
      500,
      1000,
    ]) {
      if ((r - nice).abs() / nice < 0.05) return nice.toDouble();
    }
    return double.parse(r.toStringAsFixed(1));
  }

  void _start(double rate) {
    final n = _channels!;
    final labels = _labels != null && _labels!.length == n
        ? _labels!
        : [for (var c = 0; c < n; c++) 'ch${c + 1}'];
    _info = StreamInfo(
      key: 'serial:$name',
      name: name,
      type: type,
      kind: kindFromType(type),
      rate: rate,
      labels: labels,
      units: List.filled(n, ''),
      channels: [for (var c = 0; c < n; c++) ChannelRef(0, c)],
    );
    final ring = _ring = RegularRing(n, rate);
    for (final (t, v) in _early) {
      _place(ring, t, v);
    }
    _early.clear();
    notifyListeners(); // a stream now: its tab appears
    _changes.ping();
  }

  void _place(RegularRing ring, double t, Float64List v) {
    final rate = ring.rate;
    if (ring.written == 0) {
      _anchor = t;
      ring.t0 = t;
    } else {
      final tolerance = math.max(2, (rate * 0.1).ceil());
      final gap = ((t - _anchor) * rate).round() - ring.written;
      if (gap > tolerance) {
        ring.fill(gap, v);
      } else if (gap < -tolerance) {
        // Faster than the rate (or a burst): follow the samples.
        _anchor = t - ring.written / rate;
      }
    }
    ring.add(v);
  }

  // -- SourceSession ----------------------------------------------------------

  @override
  List<StreamInfo> get streams => [?_info];

  @override
  String get label => 'Serial';

  @override
  String get titleSuffix => error != null ? ' (stopped)' : '';

  @override
  String get tooltip => describe();

  @override
  bool get groupable => false;

  @override
  String get rememberKey => 'serial:$name';

  @override
  bool get closed => _closed;

  @override
  StreamSource sourceFor(StreamInfo info) => LiveStreamSource(this, info);

  @override
  String describe() => [
    'Serial $portName',
    if (_ring != null)
      '${_ring!.channelCount} ch at ${formatNumber(_ring!.rate)} Hz'
    else if (received > 0)
      'measuring the rate…'
    else
      'waiting for data',
    if (skipped > 0) '$skipped lines skipped',
    ?error,
  ].join(' · ');

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await transport.close();
    notifyListeners();
  }

  // -- LiveData ---------------------------------------------------------------

  @override
  Listenable get changes => _changes;

  @override
  double get now => _ring == null || _ring!.written == 0 ? 0 : _ring!.end;

  @override
  List<Float64List>? columnsAt(
    List<ChannelRef> refs,
    double rate,
    int from,
    int to,
  ) => _ring == null ? null : ringColumns({0: _ring!}, refs, rate, from, to);

  @override
  (int, int)? tickRange(List<ChannelRef> refs, double rate) =>
      _ring == null ? null : ringTickRange({0: _ring!}, refs, rate);

  @override
  EventSamples events(int stream) => EventSamples.empty;
}
