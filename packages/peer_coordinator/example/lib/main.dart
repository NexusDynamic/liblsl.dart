/// A chat app built on `peer_coordinator`.
///
/// Nodes join a named room through a WebSocket hub, elect a coordinator
/// between themselves, and exchange lines over the user-message channel. See
/// `lib/src/chat/chat_session.dart` for how the messages actually travel, and
/// README.md for how to run the hub.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:peer_coordinator/peer_coordinator.dart';

import 'src/ui/connect_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // peer_coordinator logs through package:logging. Its default printer emits
  // ANSI colour, which the Flutter console renders as noise, so print plainly.
  Log.useColors = false;
  Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}',
    );
  });

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'peer_coordinator chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ConnectPage(),
    );
  }
}
