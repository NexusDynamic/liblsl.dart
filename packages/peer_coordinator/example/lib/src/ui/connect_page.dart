import 'package:flutter/material.dart';
import 'package:peer_coordinator/websocket.dart';

import '../chat/chat_session.dart';
import 'chat_page.dart';

/// Collects everything needed to build a [ChatSession], then joins.
///
/// Joining is the slow part — discovery has to run its full timeout before a
/// node can conclude that nobody else is there and elect itself — so the
/// button shows progress and failures land inline rather than in a dialog.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hubController = TextEditingController(text: 'ws://127.0.0.1:8080');
  final _roomController = TextEditingController(text: 'lounge');

  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _hubController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final session = ChatSession(
      displayName: _nameController.text.trim(),
      roomName: _roomController.text.trim(),
      transportConfig: WebSocketTransportConfig(
        hubUri: Uri.parse(_hubController.text.trim()),
      ),
    );

    final joined = await session.connect();
    if (!mounted) {
      session.dispose();
      return;
    }
    if (!joined) {
      setState(() {
        _connecting = false;
        _error = session.failureReason ?? 'Could not reach the hub.';
      });
      session.dispose();
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatPage(session: session)));
    session.dispose();
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('peer_coordinator chat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      helperText: 'Shown to everyone else in the room',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Pick a name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _hubController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Hub URL',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateHubUri,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _roomController,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _connecting ? null : _join(),
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      helperText: 'Nodes only find each other within a room',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value?.trim().isEmpty ?? true) ? 'Pick a room' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _connecting ? null : _join,
                    child: _connecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('Start a hub first:', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SelectableText(
                    'dart run peer_coordinator:hub --host 0.0.0.0 --port 8080',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mirrors what `WebSocketTransportConfig.validate` will reject, so the user
  /// finds out before a join attempt rather than after one.
  String? _validateHubUri(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || !uri.hasAuthority) return 'Not a URL';
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      return 'Must start with ws:// or wss://';
    }
    return null;
  }
}
