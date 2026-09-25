import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer/signal_viewer.dart';

/// Electrode positions of the OpenBCI UltraCortex Mark IV (16 channels; the
/// first 8 without a Daisy).
const ultracortexMk4 = [
  'Fp1', 'Fp2', 'C3', 'C4', 'P7', 'P8', 'O1', 'O2', //
  'F7', 'F8', 'F3', 'F4', 'T7', 'T8', 'P3', 'P4',
];

/// An OpenBCI Cyton (+ Daisy) streaming: an EEG stream (8 or 16 channels,
/// µV) and its accelerometer (g), one tab each. Samples are placed by the
/// board's counter; lost ones are filled by interpolation.
class CytonSession extends SourceSession implements LiveData {
  final CytonBoard board;
  final String portName;
  final List<String> labels;
  late final StreamSubscription<CytonSample> _sub;
  final _changes = Changes();
  final Stopwatch _clock = Stopwatch()..start();
  late final RegularRing _eeg = RegularRing(board.channelCount, board.rate);
  late final RegularRing _accel = RegularRing(3, board.rate);
  int received = 0;
  bool _closed = false;
  String? error;

  CytonSession._(this.board, this.portName, this.labels) {
    _sub = board.samples.listen(
      _onSample,
      onError: (Object e) {
        error = '$e';
        notifyListeners();
      },
      onDone: () {
        error ??= 'The board stopped';
        notifyListeners();
      },
    );
  }

  /// Connect to the Cyton on [port] and start streaming. [ultracortex]
  /// names the channels as the UltraCortex Mark IV's electrodes.
  static Future<CytonSession> open(
    SerialPortProvider provider,
    SerialPortInfo port, {
    bool useDaisy = true,
    bool ultracortex = true,
  }) async {
    final transport = await provider.open(port, baudRate: cytonBaudRate);
    final board = await CytonBoard.connect(transport, useDaisy: useDaisy);
    final n = board.channelCount;
    final s = CytonSession._(
      board,
      port.description.isEmpty ? port.id : port.description,
      [
        for (var c = 0; c < n; c++)
          ultracortex ? ultracortexMk4[c] : 'ch${c + 1}',
      ],
    );
    await board.start();
    return s;
  }

  void _onSample(CytonSample s) {
    if (_eeg.written == 0) {
      final t = _clock.elapsedMicroseconds / 1e6;
      _eeg.t0 = t;
      _accel.t0 = t;
    } else if (s.lost > 0) {
      _eeg.fill(s.lost, s.eeg);
      _accel.fill(s.lost, s.accel);
    }
    _eeg.add(s.eeg);
    _accel.add(s.accel);
    received++;
    if (received == 1) notifyListeners(); // its tabs appear
    _changes.ping();
  }

  int get lostSampleCount => _eeg.lost;

  // -- SourceSession ----------------------------------------------------------

  @override
  List<StreamInfo> get streams => received == 0
      ? const []
      : [
          StreamInfo(
            key: 'cyton:eeg',
            name: 'Cyton EEG',
            type: 'EEG',
            kind: Kind.eeg,
            rate: board.rate,
            labels: labels,
            units: List.filled(labels.length, 'uV'),
            channels: [
              for (var c = 0; c < labels.length; c++) ChannelRef(0, c),
            ],
          ),
          StreamInfo(
            key: 'cyton:accel',
            name: 'Cyton accelerometer',
            type: 'Accelerometer',
            kind: Kind.imu,
            rate: board.rate,
            labels: const ['x', 'y', 'z'],
            units: const ['g', 'g', 'g'],
            channels: [for (var c = 0; c < 3; c++) ChannelRef(1, c)],
          ),
        ];

  @override
  String get label => 'Cyton';

  @override
  String get titleSuffix => error != null ? ' (stopped)' : '';

  @override
  String get tooltip => describe();

  @override
  bool get groupable => false;

  @override
  String get rememberKey => 'cyton';

  @override
  bool get closed => _closed;

  @override
  StreamSource sourceFor(StreamInfo info) => LiveStreamSource(this, info);

  @override
  String describe() => [
    'OpenBCI Cyton${board.daisy ? ' + Daisy' : ''} on $portName',
    '${board.channelCount} ch at ${formatNumber(board.rate)} Hz',
    if (lostSampleCount > 0) '$lostSampleCount lost',
    if (board.dropped > 0) '${board.dropped} packets dropped',
    ?error,
  ].join(' · ');

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await board.close();
    notifyListeners();
  }

  // -- LiveData ---------------------------------------------------------------

  Map<int, RegularRing> get _rings => {0: _eeg, 1: _accel};

  @override
  Listenable get changes => _changes;

  @override
  double get now => _eeg.written == 0 ? 0 : _eeg.end;

  @override
  List<Float64List>? columnsAt(
    List<ChannelRef> refs,
    double rate,
    int from,
    int to,
  ) => ringColumns(_rings, refs, rate, from, to);

  @override
  (int, int)? tickRange(List<ChannelRef> refs, double rate) =>
      ringTickRange(_rings, refs, rate);

  @override
  EventSamples events(int stream) => EventSamples.empty;
}
