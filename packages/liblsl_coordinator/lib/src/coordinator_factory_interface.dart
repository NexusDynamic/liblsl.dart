import 'dart:async';
import 'session_config.dart';

/// Abstract interface for transport-specific factories
/// 
/// This defines the contract that all transport implementations must follow,
/// ensuring consistent API across LSL, WebSocket, and future transports.
abstract class TransportFactoryInterface {
  /// Name of this transport (e.g., 'lsl', 'websocket', 'grpc')
  String get name;
  
  /// Platforms this transport supports
  List<String> get supportedPlatforms;
  
  /// Whether this transport is available on the current platform
  bool get isAvailable;
  
  /// Initialize the transport layer
  /// 
  /// This should be called before any other operations
  Future<void> initialize([Map<String, dynamic>? config]);
  
  /// Create a new coordination session
  /// 
  /// Returns a [SessionResult] containing the session and metadata
  Future<SessionResult> createSession(SessionConfig config);
  
  /// Get an existing session by ID
  NetworkSession? getSession(String sessionId);
  
  /// List all active session IDs
  List<String> get activeSessionIds;
  
  /// Cleanup and shutdown the transport
  Future<void> dispose();
}

/// Exception thrown when transport operations fail
class TransportException implements Exception {
  final String transport;
  final String message;
  final Object? cause;
  
  const TransportException(this.transport, this.message, [this.cause]);
  
  @override
  String toString() => 'TransportException($transport): $message';
}

/// Exception thrown when a transport is not available
class TransportUnavailableException extends TransportException {
  const TransportUnavailableException(String transport) 
    : super(transport, 'Transport not available on this platform');
}