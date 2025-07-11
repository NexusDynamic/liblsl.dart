import 'package:meta/meta.dart';
import 'package:liblsl/lsl.dart';

/// Configuration for different stream layers
@immutable
class StreamLayerConfig {
  /// Unique identifier for this layer
  final String layerId;

  /// Human-readable name for this layer
  final String layerName;

  /// Stream configuration
  final StreamConfig streamConfig;

  /// Whether this layer should be pausable
  final bool isPausable;

  /// Whether this layer runs in its own isolate
  final bool useIsolate;

  /// Priority level for resource allocation
  final LayerPriority priority;

  /// Whether each node should have an outlet on this layer
  final bool requiresOutlet;

  /// Whether each node should have inlets for all other nodes
  final bool requiresInletFromAll;

  /// Custom metadata for this layer
  final Map<String, dynamic> metadata;

  const StreamLayerConfig({
    required this.layerId,
    required this.layerName,
    required this.streamConfig,
    this.isPausable = false,
    this.useIsolate = true,
    this.priority = LayerPriority.medium,
    this.requiresOutlet = true,
    this.requiresInletFromAll = true,
    this.metadata = const {},
  });

  StreamLayerConfig copyWith({
    String? layerId,
    String? layerName,
    StreamConfig? streamConfig,
    bool? isPausable,
    bool? useIsolate,
    LayerPriority? priority,
    bool? requiresOutlet,
    bool? requiresInletFromAll,
    Map<String, dynamic>? metadata,
  }) {
    return StreamLayerConfig(
      layerId: layerId ?? this.layerId,
      layerName: layerName ?? this.layerName,
      streamConfig: streamConfig ?? this.streamConfig,
      isPausable: isPausable ?? this.isPausable,
      useIsolate: useIsolate ?? this.useIsolate,
      priority: priority ?? this.priority,
      requiresOutlet: requiresOutlet ?? this.requiresOutlet,
      requiresInletFromAll: requiresInletFromAll ?? this.requiresInletFromAll,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'layerId': layerId,
      'layerName': layerName,
      'streamConfig': streamConfig.toMap(),
      'isPausable': isPausable,
      'useIsolate': useIsolate,
      'priority': priority.index,
      'requiresOutlet': requiresOutlet,
      'requiresInletFromAll': requiresInletFromAll,
      'metadata': metadata,
    };
  }

  factory StreamLayerConfig.fromMap(Map<String, dynamic> map) {
    return StreamLayerConfig(
      layerId: map['layerId'] as String,
      layerName: map['layerName'] as String,
      streamConfig: StreamConfig.fromMap(
        map['streamConfig'] as Map<String, dynamic>,
      ),
      isPausable: map['isPausable'] as bool? ?? false,
      useIsolate: map['useIsolate'] as bool? ?? true,
      priority:
          LayerPriority.values[map['priority'] as int? ??
              LayerPriority.medium.index],
      requiresOutlet: map['requiresOutlet'] as bool? ?? true,
      requiresInletFromAll: map['requiresInletFromAll'] as bool? ?? true,
      metadata: map['metadata'] as Map<String, dynamic>? ?? const {},
    );
  }
}

/// Configuration for individual stream properties
@immutable
class StreamConfig {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final int maxBuffer;
  final int chunkSize;

  const StreamConfig({
    required this.streamName,
    this.streamType = LSLContentType.eeg,
    this.channelCount = 1,
    this.sampleRate = 100.0,
    this.channelFormat = LSLChannelFormat.float32,
    this.maxBuffer = 360,
    this.chunkSize = 32,
  });

  StreamConfig copyWith({
    String? streamName,
    LSLContentType? streamType,
    int? channelCount,
    double? sampleRate,
    LSLChannelFormat? channelFormat,
    int? maxBuffer,
    int? chunkSize,
  }) {
    return StreamConfig(
      streamName: streamName ?? this.streamName,
      streamType: streamType ?? this.streamType,
      channelCount: channelCount ?? this.channelCount,
      sampleRate: sampleRate ?? this.sampleRate,
      channelFormat: channelFormat ?? this.channelFormat,
      maxBuffer: maxBuffer ?? this.maxBuffer,
      chunkSize: chunkSize ?? this.chunkSize,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'streamName': streamName,
      'streamType': streamType.value,
      'channelCount': channelCount,
      'sampleRate': sampleRate,
      'channelFormat': channelFormat.index,
      'maxBuffer': maxBuffer,
      'chunkSize': chunkSize,
    };
  }

  factory StreamConfig.fromMap(Map<String, dynamic> map) {
    final streamTypeValue = map['streamType'] as String;
    LSLContentType streamType;

    // Try to find existing content type first
    try {
      streamType = LSLContentType.values.firstWhere(
        (type) => type.value == streamTypeValue,
      );
    } catch (e) {
      // If not found, create custom type
      streamType = LSLContentType.custom(streamTypeValue);
    }

    return StreamConfig(
      streamName: map['streamName'] as String,
      streamType: streamType,
      channelCount: map['channelCount'] as int? ?? 1,
      sampleRate: map['sampleRate'] as double? ?? 100.0,
      channelFormat:
          LSLChannelFormat.values[map['channelFormat'] as int? ??
              LSLChannelFormat.float32.index],
      maxBuffer: map['maxBuffer'] as int? ?? 360,
      chunkSize: map['chunkSize'] as int? ?? 32,
    );
  }
}

/// Priority levels for stream layers
enum LayerPriority { low, medium, high, critical }

/// Protocol configuration that defines all stream layers
@immutable
class ProtocolConfig {
  /// Unique identifier for this protocol
  final String protocolId;

  /// Human-readable name for this protocol
  final String protocolName;

  /// List of all stream layers in this protocol
  final List<StreamLayerConfig> layers;

  /// Global configuration options
  final Map<String, dynamic> globalOptions;

  const ProtocolConfig({
    required this.protocolId,
    required this.protocolName,
    required this.layers,
    this.globalOptions = const {},
  });

  /// Get a layer by its ID
  StreamLayerConfig? getLayer(String layerId) {
    try {
      return layers.firstWhere((layer) => layer.layerId == layerId);
    } catch (e) {
      return null;
    }
  }

  /// Get all layers with a specific priority
  List<StreamLayerConfig> getLayersByPriority(LayerPriority priority) {
    return layers.where((layer) => layer.priority == priority).toList();
  }

  /// Get all pausable layers
  List<StreamLayerConfig> getPausableLayers() {
    return layers.where((layer) => layer.isPausable).toList();
  }

  ProtocolConfig copyWith({
    String? protocolId,
    String? protocolName,
    List<StreamLayerConfig>? layers,
    Map<String, dynamic>? globalOptions,
  }) {
    return ProtocolConfig(
      protocolId: protocolId ?? this.protocolId,
      protocolName: protocolName ?? this.protocolName,
      layers: layers ?? this.layers,
      globalOptions: globalOptions ?? this.globalOptions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'protocolId': protocolId,
      'protocolName': protocolName,
      'layers': layers.map((layer) => layer.toMap()).toList(),
      'globalOptions': globalOptions,
    };
  }

  factory ProtocolConfig.fromMap(Map<String, dynamic> map) {
    return ProtocolConfig(
      protocolId: map['protocolId'] as String,
      protocolName: map['protocolName'] as String,
      layers:
          (map['layers'] as List<dynamic>)
              .map(
                (layerMap) =>
                    StreamLayerConfig.fromMap(layerMap as Map<String, dynamic>),
              )
              .toList(),
      globalOptions: map['globalOptions'] as Map<String, dynamic>? ?? const {},
    );
  }
}

/// Predefined protocol configurations
class ProtocolConfigs {
  /// Basic coordination protocol with just coordination layer
  static ProtocolConfig get basic => ProtocolConfig(
    protocolId: 'basic',
    protocolName: 'Basic Coordination',
    layers: [
      StreamLayerConfig(
        layerId: 'coordination',
        layerName: 'Coordination Layer',
        streamConfig: StreamConfig(
          streamName: 'coordination',
          streamType: LSLContentType.markers,
          channelCount: 1,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.string,
        ),
        isPausable: false,
        useIsolate: true,
        priority: LayerPriority.critical,
        requiresOutlet: true,
        requiresInletFromAll: false, // coordinator has multiple inlets
      ),
    ],
  );

  /// Gaming protocol with coordination and game layers
  static ProtocolConfig get gaming => ProtocolConfig(
    protocolId: 'gaming',
    protocolName: 'Gaming Protocol',
    layers: [
      StreamLayerConfig(
        layerId: 'coordination',
        layerName: 'Coordination Layer',
        streamConfig: StreamConfig(
          streamName: 'coordination',
          streamType: LSLContentType.markers,
          channelCount: 1,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.string,
        ),
        isPausable: false,
        useIsolate: true,
        priority: LayerPriority.low,
        requiresOutlet: true,
        requiresInletFromAll: false,
      ),
      StreamLayerConfig(
        layerId: 'game',
        layerName: 'Game Data Layer',
        streamConfig: StreamConfig(
          streamName: 'game_data',
          streamType: LSLContentType.custom('game'),
          channelCount: 4,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.float32,
        ),
        isPausable: true,
        useIsolate: true,
        priority: LayerPriority.critical,
        requiresOutlet: true,
        requiresInletFromAll: true,
      ),
    ],
  );

  /// High-frequency protocol with coordination and hi-freq layers
  static ProtocolConfig get highFrequency => ProtocolConfig(
    protocolId: 'high_frequency',
    protocolName: 'High Frequency Protocol',
    layers: [
      StreamLayerConfig(
        layerId: 'coordination',
        layerName: 'Coordination Layer',
        streamConfig: StreamConfig(
          streamName: 'coordination',
          streamType: LSLContentType.markers,
          channelCount: 1,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.string,
        ),
        isPausable: false,
        useIsolate: true,
        priority: LayerPriority.critical,
        requiresOutlet: true,
        requiresInletFromAll: false,
      ),
      StreamLayerConfig(
        layerId: 'hi_freq',
        layerName: 'High Frequency Data Layer',
        streamConfig: StreamConfig(
          streamName: 'hi_freq_data',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 1000.0,
          channelFormat: LSLChannelFormat.float32,
        ),
        isPausable: true,
        useIsolate: true,
        priority: LayerPriority.high,
        requiresOutlet: true,
        requiresInletFromAll: true,
      ),
    ],
  );

  /// Full protocol with all layer types
  static ProtocolConfig get full => ProtocolConfig(
    protocolId: 'full',
    protocolName: 'Full Multi-Layer Protocol',
    layers: [
      StreamLayerConfig(
        layerId: 'coordination',
        layerName: 'Coordination Layer',
        streamConfig: StreamConfig(
          streamName: 'coordination',
          streamType: LSLContentType.markers,
          channelCount: 1,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.string,
        ),
        isPausable: false,
        useIsolate: true,
        priority: LayerPriority.critical,
        requiresOutlet: true,
        requiresInletFromAll: false,
      ),
      StreamLayerConfig(
        layerId: 'game',
        layerName: 'Game Data Layer',
        streamConfig: StreamConfig(
          streamName: 'game_data',
          streamType: LSLContentType.custom('game'),
          channelCount: 4,
          sampleRate: LSL_IRREGULAR_RATE,
          channelFormat: LSLChannelFormat.float32,
        ),
        isPausable: true,
        useIsolate: true,
        priority: LayerPriority.high,
        requiresOutlet: true,
        requiresInletFromAll: true,
      ),
      StreamLayerConfig(
        layerId: 'hi_freq',
        layerName: 'High Frequency Data Layer',
        streamConfig: StreamConfig(
          streamName: 'hi_freq_data',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 1000.0,
          channelFormat: LSLChannelFormat.float32,
        ),
        isPausable: true,
        useIsolate: true,
        priority: LayerPriority.high,
        requiresOutlet: true,
        requiresInletFromAll: true,
      ),
    ],
  );
}
