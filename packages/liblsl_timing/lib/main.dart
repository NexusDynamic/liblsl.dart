// lib/main.dart
import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'src/config/app_config.dart';
import 'src/data/timing_manager.dart';
import 'src/ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load configuration
  final config = await AppConfig.load();

  // Initialize TimingManager
  final timingManager = TimingManager();

  // Initialize LSL library
  print('LSL Library Version: ${LSL.version}');
  print('LSL Library Info: ${LSL.libraryInfo()}');

  runApp(LSLTimingApp(config: config, timingManager: timingManager));
}

class LSLTimingApp extends StatelessWidget {
  final AppConfig config;
  final TimingManager timingManager;

  const LSLTimingApp({
    Key? key,
    required this.config,
    required this.timingManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSL Timing Tester',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(config: config, timingManager: timingManager),
    );
  }
}
