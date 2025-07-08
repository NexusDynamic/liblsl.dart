import 'coordination_message.dart';

/// Abstraction for network transport layer
abstract class NetworkTransport {
  /// Stream of incoming messages
  Stream<CoordinationMessage> get messageStream;

  /// Whether the transport is connected
  bool get isConnected;

  /// Initialize the transport
  Future<void> initialize();

  /// Send a message
  Future<void> sendMessage(CoordinationMessage message);

  /// Subscribe to messages from a specific source
  Future<void> subscribeToSource(String sourceId);

  /// Unsubscribe from a source
  Future<void> unsubscribeFromSource(String sourceId);

  /// Dispose resources
  Future<void> dispose();
}
