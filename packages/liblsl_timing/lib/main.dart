// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'src/config/app_config.dart';
import 'src/data/timing_manager.dart';
import 'src/ui/home_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FullScreen.ensureInitialized();
  await WakelockPlus.enable();
  var logLevel = -2;
  if (kDebugMode) {
    // Enable verbose logging for debugging
    logLevel = 0;
  }
  final lslConfig = LSLApiConfig(ipv6: IPv6Mode.disable, logLevel: logLevel);
  if (kDebugMode) {
    print('Complete LSL Configuration:');
    print(lslConfig.toIniString());
  }

  LSL.setConfigContent(lslConfig);

  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    // Enable full-screen mode for mobile platforms
    FullScreen.setFullScreen(true);
    // request permissions.
    final notificationStatus = await Permission.notification.request();
    final nearbyDevicesStatus = await Permission.location.request();
    if (notificationStatus.isDenied || nearbyDevicesStatus.isDenied) {
      // Handle the case where permissions are denied
      if (kDebugMode) {
        print('Notification permission status: $notificationStatus');
        print('Nearby devices permission status: $nearbyDevicesStatus');
      }
    } else {
      // Permissions granted, proceed with app initialization
      if (kDebugMode) {
        print('Notification permission granted: $notificationStatus');
        print('Nearby devices permission granted: $nearbyDevicesStatus');
      }
    }
  }

  final refreshRateControl = FlutterRefreshRateControl();
  // Request high refresh rate
  try {
    bool success = await refreshRateControl.requestHighRefreshRate();
    if (success) {
      if (kDebugMode) {
        print('High refresh rate requested successfully.');
      }
    } else {
      if (kDebugMode) {
        print('Failed to enable high refresh rate');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error: $e');
    }
  }

  // Ensure multicast lock is acquired
  final multicastLock = FlutterMulticastLock();
  await multicastLock
      .acquireMulticastLock()
      .then((_) {
        if (kDebugMode) {
          print('Multicast lock acquired successfully.');
        }
      })
      .catchError((e) {
        if (kDebugMode) {
          print('Failed to acquire multicast lock: $e');
        }
      });
  // Load configuration
  final config = await AppConfig.load();

  // Initialize TimingManager
  final timingManager = TimingManager(config);

  // Initialize LSL library
  if (kDebugMode) {
    print('LSL Library Version: ${LSL.version}');
    print('LSL Library Info: ${LSL.libraryInfo()}');
  }

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      useOnlyLangCode: true,
      useFallbackTranslations: true,
      child: LSLTimingApp(config: config, timingManager: timingManager),
    ),
  );
}

class LSLTimingApp extends StatelessWidget {
  final AppConfig config;
  final TimingManager timingManager;

  const LSLTimingApp({
    super.key,
    required this.config,
    required this.timingManager,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSL Timing Tests',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: FPSoverlay(
        child: HomePage(config: config, timingManager: timingManager),
      ),
    );
  }
}

class FPSoverlay extends StatefulWidget {
  final Widget child;

  const FPSoverlay({super.key, required this.child});

  @override
  State<FPSoverlay> createState() => _FPSoverlayState();
}

class _FPSoverlayState extends State<FPSoverlay> {
  final ValueNotifier<int> _fps = ValueNotifier(0);
  double _reportedFps = 0;
  int _frameCount = 0;
  DateTime _lastUpdate = DateTime.now();
  final List<double> _fpsHistory = List<double>.filled(10, 0.0);
  final Completer<void> _fpsCompleter = Completer<void>();
  late final Display _display;

  @override
  void initState() {
    super.initState();
    _display = WidgetsBinding.instance.platformDispatcher.views.first.display;
    // Start the FPS calculation timer
    _startFPSTimer();
  }

  @override
  void dispose() {
    _fps.dispose();
    _fpsCompleter.complete();
    _fpsHistory.setAll(0, List<double>.filled(_fpsHistory.length, 0.0));
    super.dispose();
  }

  /// Starts a timer to calculate and update the FPS.
  /// This sets a frame callback to update the FPS every frame.
  /// Until the completer is completed, it will keep updating the FPS.
  /// this will also force rendering each frame.
  void _startFPSTimer() {
    WidgetsBinding.instance.scheduleFrameCallback((Duration timeStamp) {
      if (_fpsCompleter.isCompleted) return;
      _frameCallback(timeStamp);
    }, scheduleNewFrame: true);
  }

  void _frameCallback(Duration _) {
    if (_fpsCompleter.isCompleted) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate).inMilliseconds;
    _lastUpdate = now;

    // Update the frame count
    _frameCount++;
    if (elapsed > 0) {
      final index = _frameCount % _fpsHistory.length;
      _fpsHistory[index] = (1000 / elapsed);
      // update now and then
      if (index == _fpsHistory.length - 1) {
        // Calculate the average FPS from the history
        final averageFps =
            _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;
        _fps.value = averageFps.round();
      }
    }

    // update reported FPS
    _reportedFps = _display.refreshRate;

    // Schedule the next frame callback
    WidgetsBinding.instance.scheduleFrameCallback(
      _frameCallback,
      rescheduling: true,
      scheduleNewFrame: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 10,
          right: 10,
          child: ValueListenableBuilder<int>(
            valueListenable: _fps,
            builder: (context, fps, _) {
              return Text(
                'FPS\n$fps\n$_reportedFps',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  backgroundColor: Colors.black54,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
