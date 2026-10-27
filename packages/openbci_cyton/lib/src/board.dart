import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:serial_transport/serial_transport.dart';

import 'impedance.dart';
import 'protocol.dart';
import 'settings.dart';

/// Baud rate of the Cyton's USB dongle.
const cytonBaudRate = 115200;

/// A Cyton (with or without a Daisy) on a serial port: configures it,
/// streams its samples, logs to its SD card.
///
/// ```dart
/// final t = await SerialPortProvider.platform().open(port,
///     baudRate: cytonBaudRate);
/// final board = await CytonBoard.connect(t);
/// board.samples.listen((s) => print(s.eeg));
/// await board.start();
/// ```
///
/// Commands that the board answers wait for the answer and throw if it
/// reports a failure. While streaming, the board does not answer: channel
/// settings, test signals, lead-off and markers are sent without waiting,
/// and the other commands need [stop] first.
class CytonBoard {
  final SerialTransport transport;
  late final StreamSubscription<Uint8List> _sub;
  final _samples = StreamController<CytonSample>.broadcast();
  final _text = StringBuffer();
  Completer<String>? _reply;
  CytonDecoder _decoder = CytonDecoder();
  bool _streaming = false;
  final List<int> _gains = List.filled(16, 24);
  final List<CytonChannelSettings> _channels = List.filled(
    16,
    const CytonChannelSettings(),
  );
  List<CytonChannelSettings>? _beforeTest;

  /// Time since bytes last came in.
  final _quiet = Stopwatch()..start();

  /// Markers waiting their turn, and the time since the last was sent.
  Future<void> _markers = Future.value();
  final _sinceMarker = Stopwatch();

  /// What the board said on reset (chip ids, firmware).
  String info = '';

  /// Whether a Daisy is used (16 channels).
  bool daisy = false;

  /// The ADS1299's sampling rate. Above 250 Hz the board does not stream
  /// (it logs to the SD card only).
  CytonSampleRate sampleRate = CytonSampleRate.hz250;

  /// What the aux bytes of the samples hold.
  CytonBoardMode boardMode = CytonBoardMode.defaults;

  /// The internal test signal on all channels, if any.
  CytonTestSignal? testSignal;

  /// The SD card file being written (e.g. `OBCI_24.TXT`), or null.
  String? sdFile;

  CytonBoard._(this.transport) {
    _sub = transport.input.listen(
      _onBytes,
      onError: (Object e) => _samples.addError(e),
      onDone: () => _samples.close(),
    );
  }

  int get channelCount => daisy ? 16 : 8;

  /// Samples per second over the dongle: 250, or 125 with a Daisy (two
  /// packets a sample).
  double get rate => daisy ? 125 : 250;

  /// Whether samples arrive while streaming: not above 250 Hz.
  bool get live => sampleRate == CytonSampleRate.hz250;

  bool get streaming => _streaming;

  /// Samples while streaming.
  Stream<CytonSample> get samples => _samples.stream;

  /// Packets dropped so far (garbled, or a Daisy half without the other).
  int get dropped => _decoder.dropped;

  /// Gain of each channel (16), as set.
  List<int> get gains => List.unmodifiable(_gains);

  /// Settings of each channel in use, as set.
  List<CytonChannelSettings> get channels =>
      List.unmodifiable(_channels.take(channelCount));

  /// Reset the board on [transport] and find out whether it has a Daisy.
  /// With [useDaisy] false, a Daisy is left out (8 channels). The board
  /// keeps its sampling rate and board mode through a reset: they are set
  /// to [sampleRate] and [boardMode] if given, and read otherwise.
  static Future<CytonBoard> connect(
    SerialTransport transport, {
    bool useDaisy = true,
    CytonSampleRate? sampleRate,
    CytonBoardMode? boardMode,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final b = CytonBoard._(transport);
    try {
      // It may still be streaming from an earlier session.
      await transport.write(ascii.encode('s'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      b._text.clear();
      b.info = await b.command('v', timeout: timeout);
      if (!b.info.contains(r'$$$')) {
        throw StateError(
          'No reply from the board (is it on, and the dongle switched to '
          'GPIO_6?): ${b.info.trim()}',
        );
      }
      final hasDaisy = b.info.toLowerCase().contains('daisy');
      b.daisy = hasDaisy && useDaisy;
      // A reset attaches the Daisy; the board says nothing to C then.
      if (hasDaisy) {
        await b.command(
          b.daisy ? 'C' : 'c',
          timeout: const Duration(milliseconds: 500),
        );
      }
      await b.resetChannels();
      if (sampleRate != null) {
        await b.setSampleRate(sampleRate);
      } else {
        b.sampleRate = await b.querySampleRate();
      }
      if (boardMode != null) {
        await b.setBoardMode(boardMode);
      } else {
        b.boardMode = await b.queryBoardMode();
      }
      return b;
    } catch (_) {
      await b.close();
      rethrow;
    }
  }

  void _onBytes(Uint8List bytes) {
    _quiet.reset();
    if (_streaming) {
      for (final s in _decoder.add(bytes)) {
        if (!_samples.isClosed) _samples.add(s);
      }
      return;
    }
    _text.write(latin1.decode(bytes));
    final reply = _reply;
    if (reply != null && _text.toString().contains(r'$$$')) {
      _reply = null;
      reply.complete(_text.toString());
      _text.clear();
    }
  }

  /// Send [cmd] and wait for the reply (up to `$$$`, or what came in
  /// [timeout]). Not while streaming.
  Future<String> command(
    String cmd, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_streaming) throw StateError('Stop streaming first');
    _text.clear();
    final reply = _reply = Completer<String>();
    await transport.write(ascii.encode(cmd));
    return reply.future.timeout(
      timeout,
      onTimeout: () {
        _reply = null;
        final t = _text.toString();
        _text.clear();
        return t;
      },
    );
  }

  /// Send [cmd] without waiting for a reply.
  Future<void> _send(String cmd) => transport.write(ascii.encode(cmd));

  /// [cmd], with its reply checked when not streaming.
  Future<void> _sendChecked(String cmd, String what) async {
    if (_streaming) return _send(cmd);
    final reply = await command(cmd);
    if (reply.contains('Failure')) {
      throw StateError('$what: ${_trim(reply)}');
    }
  }

  static String _trim(String reply) => reply.replaceAll(r'$$$', '').trim();

  void _checkChannel(int channel) {
    if (channel < 1 || channel > channelCount) {
      throw RangeError.range(channel, 1, channelCount, 'channel');
    }
  }

  /// Set channel [channel] (1-16).
  Future<void> configureChannel(int channel, CytonChannelSettings s) async {
    _checkChannel(channel);
    await _sendChecked(s.commandFor(channel), 'Channel $channel');
    _channels[channel - 1] = s;
    _gains[channel - 1] = s.gain;
  }

  /// Switch channel [channel] (1-16) on or off, keeping its settings. A
  /// channel that is off reads 0.
  Future<void> setChannelEnabled(int channel, bool on) async {
    _checkChannel(channel);
    await _send(cytonChannelSwitch(channel, on));
    _channels[channel - 1] = _channels[channel - 1].copyWith(enabled: on);
  }

  /// Restore the default settings of all channels (`d`).
  Future<void> resetChannels() async {
    await _sendChecked('d', 'Default channel settings');
    _channels.fillRange(0, 16, const CytonChannelSettings());
    _gains.fillRange(0, 16, 24);
    _beforeTest = null;
    testSignal = null;
  }

  /// Connect all channels to the internal test [signal] (keeping their
  /// gains; channels that are off show it too), or with null, restore the
  /// settings they had before.
  Future<void> setTestSignal(CytonTestSignal? signal) async {
    if (signal == null) {
      final before = _beforeTest;
      _beforeTest = null;
      testSignal = null;
      if (before == null) return;
      for (var c = 1; c <= channelCount; c++) {
        await configureChannel(c, before[c - 1]);
      }
      return;
    }
    await _sendChecked(signal.code, 'Test signal');
    _beforeTest ??= List.of(_channels);
    testSignal = signal;
    final input = signal == CytonTestSignal.ground
        ? CytonInput.shorted
        : CytonInput.testSignal;
    for (var c = 0; c < 16; c++) {
      _channels[c] = _channels[c].copyWith(input: input, enabled: true);
    }
  }

  /// Set the sampling rate (not while streaming). It holds until the board
  /// is switched off.
  Future<void> setSampleRate(CytonSampleRate rate) async {
    final reply = await command('~${rate.code}');
    if (!reply.contains('Success')) {
      throw StateError('Sampling rate: ${_trim(reply)}');
    }
    sampleRate = rate;
  }

  /// Ask the board for its sampling rate (not while streaming).
  Future<CytonSampleRate> querySampleRate() async {
    final reply = await command('~~');
    final m = RegExp(r'(\d+)\s*Hz').firstMatch(reply);
    final rate = m == null ? null : CytonSampleRate.of(int.parse(m[1]!));
    if (rate == null) {
      throw StateError('Sampling rate: ${_trim(reply)}');
    }
    return sampleRate = rate;
  }

  /// Set what the aux bytes hold (not while streaming). It holds until the
  /// board is switched off.
  Future<void> setBoardMode(CytonBoardMode mode) async {
    final reply = await command('/${mode.code}');
    if (!reply.contains(mode.reply)) {
      throw StateError('Board mode: ${_trim(reply)}');
    }
    boardMode = mode;
  }

  /// Ask the board for its mode (not while streaming).
  Future<CytonBoardMode> queryBoardMode() async {
    final reply = await command('//');
    for (final m in CytonBoardMode.values) {
      if (reply.contains(m.reply)) return boardMode = m;
    }
    throw StateError('Board mode: ${_trim(reply)}');
  }

  /// Put a marker with [value] into the samples (in
  /// [CytonBoardMode.marker], while streaming): [CytonSample.marker] of
  /// the next sample, and in an SD card recording. Only values that the
  /// board cannot take for commands are allowed ([cytonMarkerIsSafe]):
  /// 128-239, or one of [cytonSafeMarkerChars]. The board holds one
  /// marker per sample, so markers are sent two samples apart at least
  /// (in turn). Markers sent in the first moments of streaming can be
  /// lost.
  Future<void> marker(int value) {
    if (!cytonMarkerIsSafe(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'A marker must be 128-239 or one of $cytonSafeMarkerChars (others '
            'are commands if the radio loses part of the marker)',
      );
    }
    if (boardMode != CytonBoardMode.marker) {
      throw StateError('Markers need the marker board mode');
    }
    final gap = Duration(microseconds: (2e6 / rate).round());
    return _markers = _markers.then((_) async {
      final wait = gap - _sinceMarker.elapsed;
      if (_sinceMarker.isRunning && wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      await transport.write([0x60, value]);
      _sinceMarker
        ..reset()
        ..start();
    });
  }

  /// Apply the lead-off current (for measuring impedance) to the [p] and
  /// [n] inputs of channel [channel], or with both false, remove it.
  Future<void> setLeadOff(int channel, {bool p = false, bool n = false}) {
    _checkChannel(channel);
    return _sendChecked(
      'z${cytonChannelChar(channel)}${p ? 1 : 0}${n ? 1 : 0}Z',
      'Lead-off on channel $channel',
    );
  }

  /// Measure the impedance (Ω) of the electrode on [pin] of channel
  /// [channel], while streaming, as the OpenBCI GUI does: the channel at
  /// gain 1 without a reference, the lead-off current on the pin, and the
  /// amplitude of the signal at [cytonLeadOffHz] over [window] (after
  /// [settle]). The channel's settings are restored afterwards.
  ///
  /// With a Daisy, the board streams the mean of two samples at 250 Hz,
  /// which leaves cos(π · 31.25 / 250) ≈ 0.92 of the signal's amplitude;
  /// the amplitude is corrected for it (the OpenBCI GUI does not, so it
  /// reads impedances about 8% lower with a Daisy).
  Future<double> measureImpedance(
    int channel, {
    CytonLeadOff pin = CytonLeadOff.n,
    Duration window = const Duration(seconds: 2),
    Duration settle = const Duration(milliseconds: 500),
  }) async {
    _checkChannel(channel);
    if (!_streaming || !live) {
      throw StateError('Measuring impedance needs streaming at 250 Hz');
    }
    final before = _channels[channel - 1];
    final values = <double>[];
    // Whole periods of the 31.25 Hz current: 4 samples at 125 Hz, 8 at 250.
    final needed = (window.inMicroseconds * rate / 1e6 ~/ 8) * 8;
    final done = Completer<void>();
    late final StreamSubscription<CytonSample> sub;
    final settled = Stopwatch();
    sub = samples.listen((s) {
      if (!settled.isRunning || settled.elapsed < settle) return;
      values.add(s.eeg[channel - 1]);
      if (values.length >= needed && !done.isCompleted) done.complete();
    });
    try {
      await configureChannel(channel, CytonChannelSettings.impedance);
      await setLeadOff(
        channel,
        p: pin == CytonLeadOff.p,
        n: pin == CytonLeadOff.n,
      );
      settled.start();
      await done.future.timeout(
        window * 3 + settle + const Duration(seconds: 2),
      );
    } finally {
      await sub.cancel();
      await setLeadOff(channel);
      await configureChannel(channel, before);
    }
    var amplitude = toneAmplitude(values, rate);
    if (daisy) amplitude /= math.cos(math.pi * cytonLeadOffHz / 250);
    return cytonImpedanceOhms(amplitude);
  }

  /// [measureImpedance] for each of [channels] (default: all) in turn,
  /// reporting each with [onChannel].
  Future<Map<int, double>> measureImpedances({
    Iterable<int>? channels,
    CytonLeadOff pin = CytonLeadOff.n,
    Duration window = const Duration(seconds: 2),
    void Function(int channel, double ohms)? onChannel,
  }) async {
    final out = <int, double>{};
    for (final c in channels ?? [for (var c = 1; c <= channelCount; c++) c]) {
      out[c] = await measureImpedance(c, pin: pin, window: window);
      onChannel?.call(c, out[c]!);
    }
    return out;
  }

  /// Start logging to the SD card, in a file with room for [duration], and
  /// streaming (the board writes while it streams). Returns the board's
  /// reply. At rates above 250 Hz no samples arrive over the dongle.
  Future<String> startSdRecording(CytonSdDuration duration) async {
    if (_streaming) await stop();
    final reply = await command(
      duration.code,
      timeout: const Duration(seconds: 5),
    );
    final lower = reply.toLowerCase();
    final file = RegExp(r'OBCI_[0-9A-Fa-f]+\.TXT').firstMatch(reply);
    if (lower.contains('fail') || lower.contains('format') || file == null) {
      // A file may have been opened all the same.
      await command('j', timeout: const Duration(seconds: 1));
      throw StateError('SD card: ${_trim(reply)}');
    }
    sdFile = file[0];
    await start();
    return _trim(reply);
  }

  /// Stop logging to the SD card and close the file, and stop streaming.
  /// Returns the board's summary (e.g. its write times), if it gave one.
  Future<String> stopSdRecording() async {
    if (sdFile == null) return '';
    await stop();
    sdFile = null;
    final reply = await command('j', timeout: const Duration(seconds: 3));
    return _trim(reply);
  }

  /// The firmware's version, e.g. `v3.1.2` (not while streaming).
  Future<String> firmwareVersion() async => _trim(await command('V'));

  /// The registers of the ADS1299s and the accelerometer, as the board
  /// lists them (not while streaming).
  Future<String> registers() async =>
      _trim(await command('?', timeout: const Duration(seconds: 3)));

  /// Reset the board (not while streaming): the channels return to their
  /// defaults; the sampling rate and board mode stay.
  Future<String> softReset() async {
    info = await command('v', timeout: const Duration(seconds: 3));
    if (daisy) {
      await command('C', timeout: const Duration(milliseconds: 500));
    } else if (info.toLowerCase().contains('daisy')) {
      await command('c', timeout: const Duration(milliseconds: 500));
    }
    _channels.fillRange(0, 16, const CytonChannelSettings());
    _gains.fillRange(0, 16, 24);
    _beforeTest = null;
    testSignal = null;
    return _trim(info);
  }

  /// Start streaming samples.
  Future<void> start() async {
    if (_streaming) return;
    _decoder = CytonDecoder(daisy: daisy, gains: _gains, mode: boardMode);
    _streaming = true;
    await transport.write(ascii.encode('b'));
  }

  /// Stop streaming.
  Future<void> stop() async {
    if (!_streaming) return;
    await transport.write(ascii.encode('s'));
    // Let the packets on their way (the dongle holds some) arrive before
    // replies are read: until nothing comes for 100 ms.
    final waited = Stopwatch()..start();
    _quiet.reset();
    while (_quiet.elapsedMilliseconds < 100 &&
        waited.elapsedMilliseconds < 1500) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _streaming = false;
    _text.clear();
  }

  /// Stop (closing an SD card file) and close the port.
  Future<void> close() async {
    try {
      await stopSdRecording();
      await stop();
    } catch (_) {
      // The port may be gone.
    }
    await _sub.cancel();
    await transport.close();
    await _samples.close();
  }
}
