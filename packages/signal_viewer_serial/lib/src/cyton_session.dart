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

/// What a Cyton channel can be used for, one stream (tab) each.
const cytonRoles = [Kind.eeg, Kind.emg, Kind.other];

/// An OpenBCI Cyton (+ Daisy) streaming: its channels in a stream per role
/// (EEG, EMG, other; µV), and its accelerometer (g) or, in the marker
/// board mode, its markers. Samples are placed by the board's counter;
/// lost ones are filled by interpolation, and a pause leaves a gap.
///
/// Its methods change the board's settings; they throw what the board
/// reports.
class CytonSession extends SourceSession implements LiveData {
  final CytonBoard board;
  final String portName;
  final List<String> labels;

  /// What each channel is used for (one of [cytonRoles]).
  final List<Kind> roles;
  late final StreamSubscription<CytonSample> _sub;
  final _changes = Changes();
  final Stopwatch _clock = Stopwatch()..start();
  late final RegularRing _eeg = RegularRing(board.channelCount, board.rate);
  late final RegularRing _accel = RegularRing(3, board.rate);
  final _markers = IrregularLog(1, strings: true);
  int received = 0;
  int markerCount = 0;
  bool _closed = false;
  bool _resumed = false;
  String? error;

  CytonSession._(this.board, this.portName, this.labels)
    : roles = List.filled(board.channelCount, Kind.eeg) {
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

  /// Connect to the Cyton on [port] and start streaming at 250 Hz.
  /// [ultracortex] names the channels as the UltraCortex Mark IV's
  /// electrodes; [markers] puts the board in the marker mode (no
  /// accelerometer).
  static Future<CytonSession> open(
    SerialPortProvider provider,
    SerialPortInfo port, {
    bool useDaisy = true,
    bool ultracortex = true,
    bool markers = false,
  }) async {
    final transport = await provider.open(port, baudRate: cytonBaudRate);
    final board = await CytonBoard.connect(
      transport,
      useDaisy: useDaisy,
      sampleRate: CytonSampleRate.hz250,
      boardMode: markers ? CytonBoardMode.marker : CytonBoardMode.defaults,
    );
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

  double get _now => _clock.elapsedMicroseconds / 1e6;

  void _onSample(CytonSample s) {
    if (_eeg.written == 0) {
      final t = _now;
      _eeg.t0 = t;
      _accel.t0 = t;
    } else if (_resumed) {
      // After a pause: an empty gap for the time it lasted.
      final gap = ((_now - _eeg.end) * board.rate).floor();
      if (gap > 0) {
        final nan = List.filled(board.channelCount, double.nan);
        _eeg.fill(gap, nan);
        _accel.fill(gap, const [double.nan, double.nan, double.nan]);
        _eeg.lost -= gap;
        _accel.lost -= gap;
      }
    } else if (s.lost > 0) {
      _eeg.fill(s.lost, s.eeg);
      _accel.fill(s.lost, s.accel);
    }
    _resumed = false;
    _eeg.add(s.eeg);
    _accel.add(s.accel);
    final m = s.marker;
    if (m != null) {
      _markers.add(
        _eeg.end - 1 / board.rate,
        [m.toDouble()],
        0,
        [cytonMarkerLabel(m)],
      );
      markerCount++;
    }
    received++;
    if (received == 1) notifyListeners(); // its tabs appear
    _changes.ping();
  }

  int get lostSampleCount => _eeg.lost;

  /// Whether samples are coming in (not paused, not logging above 250 Hz).
  bool get live => board.streaming && board.live;

  // -- board ------------------------------------------------------------------

  Future<T> _change<T>(Future<T> Function() f) async {
    try {
      return await f();
    } finally {
      notifyListeners();
    }
  }

  /// Stop streaming for a while.
  Future<void> pause() => _change(board.stop);

  /// Stream again after [pause].
  Future<void> resume() => _change(() async {
    if (board.streaming) return;
    _resumed = true;
    await board.start();
  });

  /// Set channel [channel] (1-16).
  Future<void> configure(int channel, CytonChannelSettings settings) =>
      _change(() => board.configureChannel(channel, settings));

  Future<void> setEnabled(int channel, bool on) =>
      _change(() => board.setChannelEnabled(channel, on));

  Future<void> resetChannels() => _change(board.resetChannels);

  Future<void> setTestSignal(CytonTestSignal? signal) =>
      _change(() => board.setTestSignal(signal));

  /// Use channel [channel] (1-16) as [role], which moves it to that
  /// role's tab.
  void setRole(int channel, Kind role) {
    if (roles[channel - 1] == role) return;
    roles[channel - 1] = role;
    notifyListeners();
  }

  /// Put a marker with [value] into the board's samples, see
  /// [CytonBoard.marker].
  Future<void> marker(int value) => board.marker(value);

  /// Log to the SD card at [rate], with room for [duration]; above 250 Hz
  /// nothing streams meanwhile. Returns the board's reply.
  Future<String> startSd(CytonSdDuration duration, CytonSampleRate rate) =>
      _change(() async {
        if (rate != board.sampleRate) {
          await board.stop();
          await board.setSampleRate(rate);
        }
        _resumed = true;
        try {
          return await board.startSdRecording(duration);
        } catch (_) {
          // Back to streaming as before.
          if (board.sampleRate != CytonSampleRate.hz250) {
            await board.setSampleRate(CytonSampleRate.hz250);
          }
          await board.start();
          rethrow;
        }
      });

  /// Close the SD card file and stream (at 250 Hz) again. Returns the
  /// board's summary.
  Future<String> stopSd() => _change(() async {
    final summary = await board.stopSdRecording();
    if (board.sampleRate != CytonSampleRate.hz250) {
      await board.setSampleRate(CytonSampleRate.hz250);
    }
    _resumed = true;
    await board.start();
    return summary;
  });

  /// Measure the impedance of [channels] (1-16) in turn, see
  /// [CytonBoard.measureImpedance].
  Future<Map<int, double>> measureImpedances(
    Iterable<int> channels, {
    CytonLeadOff pin = CytonLeadOff.n,
    void Function(int channel, double ohms)? onChannel,
  }) => _change(
    () => board.measureImpedances(
      channels: channels,
      pin: pin,
      onChannel: onChannel,
    ),
  );

  // -- SourceSession ----------------------------------------------------------

  List<StreamInfo> _roleStreams() => [
    for (final role in cytonRoles)
      if (roles.contains(role)) _roleStream(role),
  ];

  StreamInfo _roleStream(Kind role) {
    final chans = [
      for (var c = 0; c < roles.length; c++)
        if (roles[c] == role) c,
    ];
    final all = chans.length == roles.length;
    return StreamInfo(
      // A new key when its channels change, so that its tab is rebuilt.
      key: all
          ? 'cyton:${role.name}'
          : 'cyton:${role.name}:${chans.map((c) => c + 1).join(',')}',
      name: 'Cyton ${role == Kind.other ? 'other' : role.label}',
      type: role == Kind.other ? '' : role.label,
      kind: role,
      rate: board.rate,
      labels: [for (final c in chans) labels[c]],
      units: List.filled(chans.length, 'uV'),
      channels: [for (final c in chans) ChannelRef(0, c)],
    );
  }

  @override
  List<StreamInfo> get streams => received == 0
      ? const []
      : [
          ..._roleStreams(),
          if (board.boardMode == CytonBoardMode.marker)
            const StreamInfo(
              key: 'cyton:markers',
              name: 'Cyton markers',
              type: 'Markers',
              kind: Kind.event,
              rate: 0,
              labels: ['marker'],
              units: [''],
              channels: [ChannelRef(2, 0)],
            )
          else
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
  String get titleSuffix => error != null
      ? ' (stopped)'
      : !board.streaming
      ? ' (paused)'
      : '';

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
    if (board.sdFile != null)
      'logging to ${board.sdFile} at ${board.sampleRate.hz} Hz'
          '${board.live ? '' : ' (no live data above 250 Hz)'}',
    if (!board.streaming) 'paused',
    if (board.testSignal != null) 'test signal: ${board.testSignal!.label}',
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
  EventSamples events(int stream) =>
      stream == 2 ? _markers.events(markers: true) : EventSamples.empty;
}
