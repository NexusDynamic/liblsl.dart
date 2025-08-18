import 'dart:async';

/// Base protocol interface for network operations
abstract class Protocol {
  /// Protocol name/identifier
  String get name;
  
  /// Protocol version for compatibility
  String get version;
  
  /// Initialize the protocol
  Future<void> initialize();
  
  /// Cleanup protocol resources
  Future<void> dispose();
}
