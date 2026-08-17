import 'package:flutter/material.dart';

import '../chat/chat_message.dart';
import '../chat/chat_session.dart';
import 'widgets/message_bubble.dart';

/// The room. Rebuilds off the [ChatSession]'s notifiers, so nothing here needs
/// to know about coordination.
class ChatPage extends StatefulWidget {
  const ChatPage({required this.session, super.key});

  final ChatSession session;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _composerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.session.messages.addListener(_scrollToLatest);
  }

  @override
  void dispose() {
    widget.session.messages.removeListener(_scrollToLatest);
    _composerController.dispose();
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    // The list is reversed, so "latest" is offset zero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _composerController.text;
    if (text.trim().isEmpty) return;
    _composerController.clear();
    _composerFocus.requestFocus();
    await widget.session.send(text);
  }

  Future<void> _leave() async {
    await widget.session.leave();
    if (mounted) Navigator.of(context).pop();
  }

  void _showRoster() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ValueListenableBuilder<List<ChatMember>>(
          valueListenable: widget.session.roster,
          builder: (context, members, _) => ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  'In the room (${members.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final member in members)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      member.name.isEmpty
                          ? '?'
                          : member.name.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(
                    member.isSelf ? '${member.name} (you)' : member.name,
                  ),
                  subtitle: member.isCoordinator
                      ? const Text('coordinator')
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.roomName),
            ValueListenableBuilder<bool>(
              valueListenable: session.isCoordinator,
              builder: (context, isCoordinator, _) =>
                  ValueListenableBuilder<List<ChatMember>>(
                    valueListenable: session.roster,
                    builder: (context, members, _) => Text(
                      '${isCoordinator ? 'coordinator' : 'participant'} · '
                      '${members.length} connected',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showRoster,
            icon: const Icon(Icons.people_outline),
            tooltip: 'Who is here',
          ),
          IconButton(
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            tooltip: 'Leave',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: session.messages,
              builder: (context, messages, _) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Nothing here yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return MessageBubble(
                      message: message,
                      isMine: message.fromUId == session.thisNodeUId,
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composerController,
                      focusNode: _composerFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
