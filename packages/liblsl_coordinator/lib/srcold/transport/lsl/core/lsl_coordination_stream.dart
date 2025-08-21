import 'dart:async';
import 'package:liblsl/lsl.dart';
import '../../../session/data_stream.dart';
import '../../../session/stream_config.dart';
import '../config/lsl_coordination_config.dart';
import '../config/lsl_stream_config.dart';
import '../config/lsl_channel_format.dart';
import '../connection/lsl_connection_manager.dart';
import 'lsl_data_stream.dart';

/// Coordination stream - a restricted DataStream subtype for network coordination
/// 
/// Coordination streams handle network topology, role assignment, and inter-node
/// communication. They are automatically managed by the coordination session
/// and cannot be directly controlled by users.
/// 
/// Key differences from regular DataStreams:
/// - Always use separate isolate from data streams
/// - Stream configuration is restricted and preset
/// - Cannot be created/destroyed by users directly
/// - Use coordination-specific polling frequency (~20Hz)
/// - Handle coordination protocol messages only
class LSLCoordinationStream extends LSLDataStream {
  final LSLCoordinationStreamConfig _coordinationConfig;
  
  /// Whether this coordination stream is user-modifiable
  bool get isUserModifiable => false;
  
  /// Whether this stream is enabled
  bool get isEnabled => _coordinationConfig.enabled;
  
  LSLCoordinationStream({
    required String nodeId,
    required String streamId,
    required LSLCoordinationStreamConfig coordinationConfig,
    required LSLConnectionManager connectionManager,
  }) : _coordinationConfig = coordinationConfig,
       super(
         streamId: streamId,
         nodeId: nodeId,
         config: _createCoordinationStreamConfig(streamId, coordinationConfig),
         connectionManager: connectionManager,
       );
  
  /// Create LSLStreamConfig from coordination config
  static LSLStreamConfig _createCoordinationStreamConfig(
    String streamId,
    LSLCoordinationStreamConfig coordinationConfig,
  ) {
    return LSLStreamConfig(
      id: streamId,
      maxSampleRate: 20.0, // Coordination frequency
      pollingFrequency: 20.0,
      channelCount: 1, // Single channel for coordination messages
      channelFormat: CoordinatorLSLChannelFormat.string,
      protocol: const ProducerConsumerProtocol(), // Coordination needs both directions
      metadata: {
        'stream_purpose': 'coordination',
        'layer': 'coordination',
        'user_modifiable': 'false',
      },
      streamType: coordinationConfig.streamType,
      sourceId: 'coord_$streamId',
      contentType: LSLContentType.eeg, // Use existing content type for coordination
      pollingConfig: coordinationConfig.pollingConfig,
    );
  }
  
  /// Start coordination stream (restricted operation)
  @override
  Future<void> start() async {
    if (!isEnabled) {
      throw CoordinationStreamException(
        'Coordination stream $streamId is disabled',
      );
    }
    
    await super.start();
  }
  
  /// User cannot directly stop coordination streams
  @override
  Future<void> stop() async {
    throw CoordinationStreamException(
      'Coordination streams cannot be stopped directly. '
      'Stop the coordination session instead.',
    );
  }
  
  /// Coordination streams handle protocol messages, not arbitrary data
  @override
  StreamSink<T>? dataSink<T>() {
    throw CoordinationStreamException(
      'Coordination streams use protocol-specific messaging. '
      'Use coordination session methods instead.',
    );
  }
  
  /// Users cannot directly access coordination data streams
  @override
  Stream<T>? dataStream<T>() {
    throw CoordinationStreamException(
      'Coordination data streams are internal. '
      'Listen to coordination session events instead.',
    );
  }
  
  /// Internal access for coordination protocol
  StreamSink<Map<String, dynamic>>? get coordinationSink => 
      super.dataSink<Map<String, dynamic>>();
  
  /// Internal access for coordination protocol
  Stream<Map<String, dynamic>>? get coordinationStream => 
      super.dataStream<Map<String, dynamic>>();
  
  /// Get coordination-specific configuration
  LSLCoordinationStreamConfig get coordinationConfig => _coordinationConfig;
  
  /// Override toString for debugging
  @override
  String toString() {
    return 'LSLCoordinationStream($streamId, enabled: $isEnabled, isolate: ${config.pollingConfig.usePollingIsolate})';
  }
}

/// Exception thrown by coordination stream operations
class CoordinationStreamException implements Exception {
  final String message;
  
  const CoordinationStreamException(this.message);
  
  @override
  String toString() => 'CoordinationStreamException: $message';
}

/// Factory for creating coordination streams
class CoordinationStreamFactory {
  /// Create a coordination stream for the given role
  static LSLCoordinationStream createForRole({
    required String nodeId,
    required String role,
    required LSLCoordinationStreamConfig config,
    required LSLConnectionManager connectionManager,
  }) {
    final streamId = 'coordination_${role}_$nodeId';
    
    return LSLCoordinationStream(
      nodeId: nodeId,
      streamId: streamId,
      coordinationConfig: config,
      connectionManager: connectionManager,
    );
  }
  
  /// Create multiple coordination streams for different roles
  static Map<String, LSLCoordinationStream> createForTopology({
    required String nodeId,
    required List<String> roles,
    required LSLCoordinationStreamConfig config,
    required LSLConnectionManager connectionManager,
  }) {
    final streams = <String, LSLCoordinationStream>{};
    
    for (final role in roles) {
      final stream = createForRole(
        nodeId: nodeId,
        role: role,
        config: config,
        connectionManager: connectionManager,
      );
      streams[role] = stream;
    }
    
    return streams;
  }
}