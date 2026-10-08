import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/settings.dart';
import 'src/ui/connect_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _prepareDevice();
  runApp(TransportTimingApp(settings: await AppSettings.load()));
}

/// Everything that keeps the platform from interfering with a run, or from
/// blocking LSL discovery. Each is best effort: a refusal costs accuracy or
/// one backend, not the app.
Future<void> _prepareDevice() async {
  Future<void> attempt(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$what: $e');
    }
  }

  await attempt('wakelock', WakelockPlus.enable);
  if (Platform.isAndroid || Platform.isIOS) {
    await attempt('fullscreen', () async {
      await FullScreen.ensureInitialized();
      FullScreen.setFullScreen(true);
    });
    // LSL finds streams by multicast, which Android ties to these.
    await attempt('permissions', () async {
      await Permission.notification.request();
      await Permission.location.request();
    });
    await attempt(
      'multicast lock',
      () => FlutterMulticastLock().acquireMulticastLock(),
    );
  }
  await attempt(
    'refresh rate',
    () => FlutterRefreshRateControl().requestHighRefreshRate(),
  );
}

class TransportTimingApp extends StatelessWidget {
  const TransportTimingApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transport Timing',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
    home: ConnectPage(settings: settings),
  );
}
