import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'protocol.dart';
import 'package:serial_transport/serial_transport.dart';

/// A simulated Cyton (+ Daisy) on the far end of a serial port: answers
/// commands as firmware 3 does and streams a 10 Hz sine per channel
/// (amplitude 10 µV × channel number) after `b`.
class FakeCyton {
  final SerialTransport port;
  final bool daisy;
  final List<String> received = [];
  Timer? _timer;
  int _packet = 0;
  int _sample = 0;
  final _pending = StringBuffer();

  FakeCyton(this.port, {this.daisy = true}) {
    port.input.listen((bytes) => _command(ascii.decode(bytes)));
  }

  void _say(String s) => port.write(ascii.encode(s));

  void _command(String text) {
    _pending.write(text);
    var s = _pending.toString();
    _pending.clear();
    while (s.isNotEmpty) {
      if (s.startsWith('x')) {
        final end = s.indexOf('X');
        if (end < 0) {
          _pending.write(s);
          return;
        }
        received.add(s.substring(0, end + 1));
        _say('Success: Channel set for ${s[1]}\$\$\$');
        s = s.substring(end + 1);
        continue;
      }
      final c = s[0];
      s = s.substring(1);
      received.add(c);
      switch (c) {
        case 'v':
          _say(
            'OpenBCI V3 8-16 channel\nOn Board ADS1299 Device ID: 0x3E\n'
            '${daisy ? 'On Daisy ADS1299 Device ID: 0x3E\n' : ''}'
            'LIS3DH Device ID: 0x33\nFirmware: v3.1.2\n\$\$\$',
          );
        case 'C':
          _say('daisy attached16\$\$\$');
        case 'c':
          _say('daisy removed\$\$\$');
        case 'd':
          _say('updating channel settings to default\$\$\$');
        case 'b':
          _timer ??= Timer.periodic(
            const Duration(milliseconds: 20),
            (_) => _stream(),
          );
        case 's':
          _timer?.cancel();
          _timer = null;
      }
    }
  }

  /// 20 ms of packets: 5 samples (250 Hz) or 2.5 (125 Hz, 2 packets each).
  void _stream() {
    final bytes = <int>[];
    for (var k = 0; k < 5; k++) {
      final n = _packet++;
      final t = _sample / (daisy ? 125 : 250);
      double sine(int ch) => 10.0 * ch * math.sin(2 * math.pi * 10 * t);
      // Daisy: even packets carry channels 9-16, odd ones 1-8.
      final upper = daisy && n.isEven;
      bytes.addAll(
        encodeCytonPacket(n, [
          for (var i = 0; i < 8; i++) sine(upper ? i + 9 : i + 1),
        ], accel: n % 10 == 1 ? [0.0, 0.5, 1.0] : [0.0, 0.0, 0.0]),
      );
      if (!upper) _sample++;
    }
    port.write(bytes);
  }

  void stop() => _timer?.cancel();
}
