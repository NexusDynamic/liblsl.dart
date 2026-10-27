import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'impedance.dart';
import 'protocol.dart';
import 'package:serial_transport/serial_transport.dart';

/// A simulated Cyton (+ Daisy) on the far end of a serial port: answers
/// commands as firmware 3.1.2 does and streams a 10 Hz sine per channel
/// (amplitude 10 µV × channel number) after `b`. A channel with the
/// lead-off current on (`z`) carries a 31.25 Hz signal for an electrode
/// of [impedanceOhms].
class FakeCyton {
  final SerialTransport port;
  final bool daisy;
  final List<String> received = [];

  /// Impedance of every electrode, for the lead-off signal.
  double impedanceOhms;
  Timer? _timer;
  int _packet = 0;
  int _sample = 0;
  final _pending = StringBuffer();
  bool _daisyOn;
  String _rate = '6';
  String _mode = '0';

  /// Markers (time received in µs, value) not yet sent.
  final _markers = <(int, int)>[];
  final _clock = Stopwatch()..start();
  int _tick = 0;
  int _files = 0;
  bool _logging = false;
  final _gains = List.filled(16, 24);
  final _off = List.filled(16, false);
  final _leadOff = List.filled(16, false);

  FakeCyton(this.port, {this.daisy = true, this.impedanceOhms = 10000})
    : _daisyOn = daisy {
    port.input.listen((bytes) => _command(latin1.decode(bytes)));
  }

  static const _rates = {
    '0': 16000,
    '1': 8000,
    '2': 4000,
    '3': 2000,
    '4': 1000,
    '5': 500,
    '6': 250,
  };
  static const _modes = {
    '0': 'default',
    '1': 'debug',
    '2': 'analog',
    '3': 'digital',
    '4': 'marker',
  };

  bool get streaming => _timer != null;

  void _say(String s) => port.write(ascii.encode(s));

  /// A reply, which the board leaves out while streaming.
  void _reply(String s) {
    if (!streaming) _say(s);
  }

  int _channel(String c) => '12345678QWERTYUI'.indexOf(c);

  void _command(String text) {
    _pending.write(text);
    var s = _pending.toString();
    _pending.clear();
    while (s.isNotEmpty) {
      // Multi-character commands: wait for all of them.
      final (prefix, length) = switch (s[0]) {
        'x' => ('x', 9),
        'z' => ('z', 5),
        '~' || '/' || '`' => (s[0], 2),
        _ => ('', 1),
      };
      if (s.length < length) {
        _pending.write(s);
        return;
      }
      final cmd = s.substring(0, length);
      s = s.substring(length);
      received.add(cmd);
      if (prefix.isNotEmpty) {
        _multi(cmd);
      } else {
        _single(cmd);
      }
    }
  }

  void _multi(String cmd) {
    switch (cmd[0]) {
      case 'x':
        final ch = _channel(cmd[1]);
        _off[ch] = cmd[2] == '1';
        _gains[ch] = cytonGains[int.parse(cmd[3])];
        _reply('Success: Channel set for ${cmd[1]}\$\$\$');
      case 'z':
        _leadOff[_channel(cmd[1])] = cmd[2] == '1' || cmd[3] == '1';
        _reply('Success: Lead off set for ${cmd[1]}\$\$\$');
      case '~':
        if (cmd[1] == '~') {
          _say('Success: Sample rate is ${_rates[_rate]}Hz\$\$\$');
        } else if (_rates.containsKey(cmd[1])) {
          _rate = cmd[1];
          _say('Success: Sample rate is ${_rates[_rate]}Hz\$\$\$');
        } else {
          _say('Failure: sample value out of bounds\$\$\$');
        }
      case '/':
        if (cmd[1] == '/') {
          _say('Success: ${_modes[_mode]}\$\$\$');
        } else if (_modes.containsKey(cmd[1])) {
          _mode = cmd[1];
          _say('Success: ${_modes[_mode]}\$\$\$');
        } else {
          _say('Failure: board mode value out of bounds.\$\$\$');
        }
      case '`':
        // A byte, extended to 16 bits with its sign.
        if (_mode == '4') {
          _markers.add((
            _clock.elapsedMicroseconds,
            cmd.codeUnitAt(1).toSigned(8) & 0xFFFF,
          ));
        }
    }
  }

  void _single(String c) {
    switch (c) {
      case 'v':
        _daisyOn = daisy;
        _defaults();
        _say(
          'OpenBCI V3 8-16 channel\nOn Board ADS1299 Device ID: 0x3E\n'
          '${daisy ? 'On Daisy ADS1299 Device ID: 0x3E\n' : ''}'
          'LIS3DH Device ID: 0x33\nFirmware: v3.1.2\n\$\$\$',
        );
      case 'V':
        _say('v3.1.2\$\$\$');
      case 'C':
        // Already attached: no reply.
        if (daisy && !_daisyOn) {
          _daisyOn = true;
          _say('daisy attached\$\$\$');
        }
      case 'c':
        if (_daisyOn) {
          _daisyOn = false;
          _say('daisy removed\$\$\$');
        }
      case 'd':
        _defaults();
        _reply('updating channel settings to default\$\$\$');
      case 'D':
        _reply('060110\$\$\$');
      case '?':
        _reply('Board ADS Registers\nCH1SET, 05, 68\n\$\$\$');
      case '0' || '-' || '=' || 'p' || '[' || ']':
        _reply('Success: Configured internal test signal.\$\$\$');
      case 'A' || 'S' || 'F' || 'G' || 'H' || 'J' || 'K' || 'L' || 'a':
        _files++;
        _logging = true;
        final n = _files.toRadixString(16).toUpperCase().padLeft(2, '0');
        _reply(
          'Wiring is correct and a card is present.\r\n'
          'Corresponding SD file OBCI_$n.TXT\r\n\$\$\$',
        );
      case 'j':
        if (_logging) {
          _logging = false;
          _reply(
            'SamplingRate: ${_rates[_rate]}Hz\r\nTotal Elapsed Time: 0 mS\r\n'
            'Max write time: 332 uS\r\nMin write time: 326 uS\r\n'
            'Overruns: 0\r\n\$\$\$',
          );
        }
      case 'b':
        if (_rate != '6') {
          _say('SPS over 250, will not stream data\$\$\$');
        } else {
          _tick = _clock.elapsedMicroseconds;
          _timer ??= Timer.periodic(
            const Duration(milliseconds: 20),
            (_) => _stream(),
          );
        }
      case 's':
        _timer?.cancel();
        _timer = null;
      default:
        final on = '!@#\$%^&*QWERTYUI'.indexOf(c);
        final off = '12345678qwertyui'.indexOf(c);
        if (on >= 0) _off[on] = false;
        if (off >= 0) _off[off] = true;
    }
  }

  void _defaults() {
    _gains.fillRange(0, 16, 24);
    _off.fillRange(0, 16, false);
    _leadOff.fillRange(0, 16, false);
  }

  /// 20 ms of packets: 5 samples (250 Hz) or 2.5 (125 Hz, 2 packets each).
  /// Each packet takes the marker received in its 4 ms, as the board holds
  /// one: the last.
  void _stream() {
    final bytes = <int>[];
    final from = _tick;
    _tick = _clock.elapsedMicroseconds;
    final step = (_tick - from) / 5;
    final leadOff = (impedanceOhms + cytonSeriesOhms) * cytonLeadOffAmps * 1e6;
    for (var k = 0; k < 5; k++) {
      final n = _packet++;
      final t = _sample / (_daisyOn ? 125 : 250);
      double value(int ch) {
        if (_off[ch - 1]) return 0;
        var v = 10.0 * ch * math.sin(2 * math.pi * 10 * t);
        if (_leadOff[ch - 1]) {
          // With a Daisy, the mean of two samples at 250 Hz.
          double s(double t) => math.sin(2 * math.pi * cytonLeadOffHz * t);
          v += _daisyOn
              ? leadOff * (s(t) + s(t - 1 / 250)) / 2
              : leadOff * s(t);
        }
        // Encoded at gain 24, read at the channel's gain.
        return v * _gains[ch - 1] / 24;
      }

      // Daisy: even packets carry channels 9-16, odd ones 1-8.
      final upper = _daisyOn && n.isEven;
      final eeg = [for (var i = 0; i < 8; i++) value(upper ? i + 9 : i + 1)];
      if (_mode == '4') {
        var marker = 0;
        final end = from + step * (k + 1);
        while (_markers.isNotEmpty && _markers.first.$1 < end) {
          marker = _markers.removeAt(0).$2;
        }
        bytes.addAll(
          encodeCytonPacket(
            n,
            eeg,
            aux: [marker >> 8, marker & 0xFF, 0, 0, 0, 0],
            endByte: cytonEndAnalog,
          ),
        );
      } else {
        bytes.addAll(
          encodeCytonPacket(
            n,
            eeg,
            accel: n % 10 == 1 ? [0.0, 0.5, 1.0] : [0.0, 0.0, 0.0],
          ),
        );
      }
      if (!upper) _sample++;
    }
    port.write(bytes);
  }

  void stop() => _timer?.cancel();
}
