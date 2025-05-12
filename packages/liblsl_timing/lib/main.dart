// lib/main.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'src/config/app_config.dart';
import 'src/data/timing_manager.dart';
import 'src/ui/home_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FullScreen.ensureInitialized();
  await WakelockPlus.enable();
  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    // Enable full-screen mode for mobile platforms
    FullScreen.setFullScreen(true);
  }
  // Load configuration
  final config = await AppConfig.load();

  // Initialize TimingManager
  final timingManager = TimingManager();

  // Initialize LSL library
  if (kDebugMode) {
    print('LSL Library Version: ${LSL.version}');
    print('LSL Library Info: ${LSL.libraryInfo()}');
  }

  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      startLocale: Locale('en'),
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
      title: 'TITLE'.tr(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(config: config, timingManager: timingManager),
    );
  }
}
