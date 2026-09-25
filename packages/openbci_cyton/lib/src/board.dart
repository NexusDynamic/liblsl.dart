import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:serial_transport/serial_transport.dart';

import 'protocol.dart';

/// Baud rate of the Cyton's USB dongle.
const cytonBaudRate = 115200;

/// What an ADS1299 channel measures (`x` command).
enum CytonInput {
  normal,
  shorted,
  biasMeasure,
  mvdd,
  temperature,
  testSignal,
  biasDrp,
  biasDrn,
}

/// Settings of one channel, as the `x` command sets them. The defaults are
/// the board's (`d`).
class CytonChannelSettings {
  final bool enabled;

  /// 1, 2, 4, 6, 8, 12 or 24.
  final int gain;
  final CytonInput input;

  /// Included in the bias (drive right leg) signal.
  final bool bias;

  /// Connected to SRB1 (a common reference for all channels).
  final bool srb1;

  /// Connected to SRB2 (the usual reference for EEG; off for bipolar EMG).
  final bool srb2;

  const CytonChannelSettings({
    this.enabled = true,
    this.gain = 24,
    this.input = CytonInput.normal,
    this.bias = true,
    this.srb1 = false,
    this.srb2 = true,
  });

  /// Bipolar channels (e.g. EMG): no common reference.
  static const bipolar = CytonChannelSettings(srb2: false);
}

/// The character that addresses channel [channel] (1-16) in commands.
String cytonChannelChar(int channel) {
  if (channel < 1 || channel > 16) {
    throw RangeError.range(channel, 1, 16, 'channel');
  }
  return channel <= 8 ? '$channel' : 'QWERTYUI'[channel - 9];
}

/// A Cyton (with or without a Daisy) on a serial port: configures it,
/// streams its samples.
///
/// ```dart
/// final t = await SerialPortProvider.platform().open(port,
///     baudRate: cytonBaudRate);
/// final board = await CytonBoard.connect(t);
/// board.samples.listen((s) => print(s.eeg));
/// await board.start();
/// ```
class CytonBoard {
  final SerialTransport transport;
  late final StreamSubscription<Uint8List> _sub;
  final _samples = StreamController<CytonSample>.broadcast();
  final _text = StringBuffer();
  Completer<String>? _reply;
  CytonDecoder _decoder = CytonDecoder();
  bool _streaming = false;

  /// What the board said on reset (chip ids, firmware).
  String info = '';

  /// Whether a Daisy is used (16 channels).
  bool daisy = false;

  /// Gain of each channel (16), kept for scaling.
  final List<int> gains = List.filled(16, 24);

  CytonBoard._(this.transport) {
    _sub = transport.input.listen(
      _onBytes,
      onError: (Object e) => _samples.addError(e),
      onDone: () => _samples.close(),
    );
  }

  int get channelCount => daisy ? 16 : 8;

  /// Samples per second: 250, or 125 with a Daisy (two packets a sample).
  double get rate => daisy ? 125 : 250;

  /// Samples while streaming.
  Stream<CytonSample> get samples => _samples.stream;

  /// Packets dropped so far (garbled, or a Daisy half without the other).
  int get dropped => _decoder.dropped;

  /// Reset the board on [transport] and find out whether it has a Daisy.
  /// With [useDaisy] false, a Daisy is left out (8 channels).
  static Future<CytonBoard> connect(
    SerialTransport transport, {
    bool useDaisy = true,
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
      if (hasDaisy) await b.command(b.daisy ? 'C' : 'c', timeout: timeout);
      final defaults = await b.command('d', timeout: timeout);
      if (defaults.startsWith('Failure')) {
        throw StateError('The board refused its defaults: $defaults');
      }
      b.gains.fillRange(0, 16, 24);
      return b;
    } catch (_) {
      await b.close();
      rethrow;
    }
  }

  void _onBytes(Uint8List bytes) {
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

  /// Set channel [channel] (1-16).
  Future<void> configureChannel(int channel, CytonChannelSettings s) async {
    if (!cytonGains.contains(s.gain)) {
      throw ArgumentError.value(s.gain, 'gain', 'One of $cytonGains');
    }
    int b(bool v) => v ? 1 : 0;
    // x (channel, power down, gain, input, bias, SRB2, SRB1) X, as the
    // OpenBCI SDK documents it: the default is x1060110X.
    final cmd =
        'x${cytonChannelChar(channel)}${b(!s.enabled)}'
        '${cytonGains.indexOf(s.gain)}${s.input.index}${b(s.bias)}'
        '${b(s.srb2)}${b(s.srb1)}X';
    final reply = await command(cmd);
    if (reply.startsWith('Failure')) {
      throw StateError('Channel $channel: ${reply.trim()}');
    }
    gains[channel - 1] = s.gain;
  }

  /// Start streaming samples.
  Future<void> start() async {
    _decoder = CytonDecoder(daisy: daisy, gains: List.of(gains));
    _streaming = true;
    await transport.write(ascii.encode('b'));
  }

  /// Stop streaming.
  Future<void> stop() async {
    if (!_streaming) return;
    await transport.write(ascii.encode('s'));
    _streaming = false;
  }

  /// Stop and close the port.
  Future<void> close() async {
    try {
      await stop();
    } catch (_) {
      // The port may be gone.
    }
    await _sub.cancel();
    await transport.close();
    await _samples.close();
  }
}
