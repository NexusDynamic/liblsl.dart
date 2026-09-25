@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:serial_transport/serial_transport.dart';
import 'package:test/test.dart';

/// Whether `socat` can create a virtual serial port pair here.
final _hasSocat =
    !Platform.isWindows &&
    Process.runSync('sh', ['-c', 'command -v socat']).exitCode == 0;

/// A pty pair created by socat: bytes written to one end come out of the
/// other, through the real serial port code of the native shim.
class PtyPair {
  final Process _socat;
  final String a;
  final String b;

  PtyPair._(this._socat, this.a, this.b);

  static Future<PtyPair> create() async {
    final dir = Directory.systemTemp.createTempSync('hs_pty');
    final a = '${dir.path}/a';
    final b = '${dir.path}/b';
    final socat = await Process.start('socat', [
      'pty,raw,echo=0,link=$a',
      'pty,raw,echo=0,link=$b',
    ]);
    for (var i = 0; i < 100; i++) {
      if (File(a).existsSync() && File(b).existsSync()) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return PtyPair._(socat, a, b);
  }

  void dispose() => _socat.kill();
}

void main() {
  final provider = SerialPortProvider.platform();

  test('the platform provider is native', () {
    expect(provider.isSupported, isTrue);
    expect(provider.requiresUserSelection, isFalse);
  });

  test('listPorts does not throw', () async {
    final ports = await provider.listPorts();
    for (final p in ports) {
      expect(p.id, isNotEmpty);
    }
  });

  test('opening a missing port fails with a SerialException', () async {
    await expectLater(
      provider.open(const SerialPortInfo(id: '/dev/does-not-exist')),
      throwsA(isA<SerialException>()),
    );
  });

  group(
    'over a pty pair',
    () {
      late PtyPair pty;
      setUp(() async => pty = await PtyPair.create());
      tearDown(() => pty.dispose());

      test('bytes pass both ways', () async {
        final a = await provider.open(SerialPortInfo(id: pty.a));
        final b = await provider.open(SerialPortInfo(id: pty.b));
        addTearDown(a.close);
        addTearDown(b.close);

        final fromA = <int>[];
        final fromB = <int>[];
        b.input.listen(fromA.addAll);
        a.input.listen(fromB.addAll);

        final big = Uint8List.fromList(List.generate(20000, (i) => i % 251));
        await a.write(big);
        await b.write('pong'.codeUnits);
        for (
          var i = 0;
          i < 100 && (fromA.length < big.length || fromB.length < 4);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(fromA, big);
        expect(String.fromCharCodes(fromB), 'pong');
      });

      test('a disconnect is reported', () async {
        final a = await provider.open(SerialPortInfo(id: pty.a));
        final done = Completer<void>();
        final errors = <Object>[];
        a.input.listen((_) {}, onError: errors.add, onDone: done.complete);
        pty.dispose(); // unplug
        await done.future.timeout(const Duration(seconds: 3));
        expect(errors.single, isA<SerialException>());
        await a.close();
      });
    },
    skip: _hasSocat ? false : 'socat not available',
    tags: ['pty'],
  );
}
