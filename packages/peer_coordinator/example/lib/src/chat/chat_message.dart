/// What a chat line is, and how it travels.
///
/// A chat line is carried as the `payload` of a `peer_coordinator` user
/// message, so it has to survive a JSON round trip. It also has to survive the
/// coordinator *relaying* it: the payload is forwarded verbatim, which is what
/// keeps the original author's name on the message rather than the relay's.
library;

/// Whether a line came from a person or from the coordination layer.
enum ChatMessageKind {
  /// Something a person typed.
  chat,

  /// A join, a leave, or a phase change, rendered inline.
  system,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.fromUId,
    required this.fromName,
    required this.text,
    required this.sentAt,
    this.kind = ChatMessageKind.chat,
  });

  /// A line the coordination layer generated locally. Never sent anywhere.
  ChatMessage.system({required this.id, required this.text, DateTime? sentAt})
    : fromUId = '',
      fromName = '',
      sentAt = sentAt ?? DateTime.now(),
      kind = ChatMessageKind.system;

  /// Rebuilds a line from the payload of a user message.
  ///
  /// Returns null rather than throwing when a field is missing or the wrong
  /// type: the payload arrives off the network, and one malformed message
  /// should not take down the chat.
  static ChatMessage? fromPayload(Map<String, dynamic> payload) {
    final id = payload['id'];
    final text = payload['text'];
    if (id is! String || text is! String) return null;
    final sentAtMs = payload['sentAtMs'];
    return ChatMessage(
      id: id,
      fromUId: payload['fromUId'] is String ? payload['fromUId'] as String : '',
      fromName: payload['from'] is String ? payload['from'] as String : 'anon',
      text: text,
      sentAt: sentAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(sentAtMs)
          : DateTime.now(),
    );
  }

  /// Stable per-message id. Every node dedupes on this, because a message can
  /// legitimately arrive twice — see `ChatSession`.
  final String id;

  /// The `uId` of the node that wrote the line, not of whoever relayed it.
  final String fromUId;

  /// The author's display name, i.e. their `NodeConfig.name`.
  final String fromName;

  final String text;
  final DateTime sentAt;
  final ChatMessageKind kind;

  Map<String, dynamic> toPayload() => {
    'id': id,
    'from': fromName,
    'fromUId': fromUId,
    'text': text,
    'sentAtMs': sentAt.millisecondsSinceEpoch,
  };
}
