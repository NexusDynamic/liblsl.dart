import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbci_cyton/testing.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_viewer_serial/signal_viewer_serial.dart';

final hasSocat =
    !Platform.isWindows &&
    Process.runSync('sh', ['-c', 'command -v socat']).exitCode == 0;

void main() {
  testWidgets('the Cyton dialogs lay out', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = (await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('cyton_dialogs');
      final a = '${dir.path}/a', b = '${dir.path}/b';
      final socat = await Process.start('socat', [
        'pty,raw,echo=0,link=$a',
        'pty,raw,echo=0,link=$b',
      ]);
      addTearDown(socat.kill);
      for (var i = 0; i < 100 && !File(b).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final provider = SerialPortProvider.platform();
      final far = await provider.open(SerialPortInfo(id: a));
      final fake = FakeCyton(far);
      addTearDown(() => tester.runAsync(far.close));
      addTearDown(fake.stop);
      final s = await CytonSession.open(
        provider,
        SerialPortInfo(id: b),
        markers: true,
      );
      for (var i = 0; i < 100 && s.received == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return s;
    }))!;
    addTearDown(() => tester.runAsync(session.close));

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    for (final (open, title) in [
      (showCytonSettings, 'Cyton settings'),
      (showCytonSdDialog, 'Record to the SD card'),
      (showCytonImpedance, 'Electrode impedance'),
      (showCytonMarkers, 'Markers'),
    ]) {
      open(context, session);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull, reason: title);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  }, skip: !hasSocat);
}
