import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/transport/lsl/config/lsl_coordination_config.dart';
import '../../../session/stream_config.dart';
import 'lsl_channel_format.dart';

/// LSL-specific implementation of StreamConfig
class LSLStreamConfig implements StreamConfig {
  @override
  final String id;

  @override
  final double maxSampleRate;

  @override
  final double pollingFrequency;

  @override
  final int channelCount;

  @override
  final CoordinatorLSLChannelFormat channelFormat;

  @override
  final StreamProtocol protocol;

  @override
  final Map<String, dynamic> metadata;

  /// LSL-specific properties
  final String streamType;
  final String sourceId;
  final LSLContentType contentType;

  /// Polling configuration
  final LSLPollingConfig pollingConfig;

  /// LSL transport configuration
  final LSLTransportConfig transportConfig;

  const LSLStreamConfig({
    required this.id,
    required this.maxSampleRate,
    required this.pollingFrequency,
    required this.channelCount,
    required this.channelFormat,
    required this.protocol,
    this.metadata = const {},
    this.streamType = 'data',
    required this.sourceId,
    this.contentType = LSLContentType.eeg,
    LSLPollingConfig? pollingConfig,
    LSLTransportConfig? transportConfig,
  }) : pollingConfig = pollingConfig ?? const LSLPollingConfig(),
       transportConfig = transportConfig ?? const LSLTransportConfig();

  /// Create LSLStreamConfig from existing LSLStreamInfo
  factory LSLStreamConfig.fromStreamInfo(
    LSLStreamInfo streamInfo, {
    required StreamProtocol protocol,
    double? pollingFrequency,
    LSLPollingConfig? pollingConfig,
    LSLTransportConfig? transportConfig,
  }) {
    return LSLStreamConfig(
      id: streamInfo.streamName,
      maxSampleRate: streamInfo.sampleRate,
      pollingFrequency: pollingFrequency ?? 100.0,
      channelCount: streamInfo.channelCount,
      channelFormat: CoordinatorLSLChannelFormat.fromLSL(
        streamInfo.channelFormat,
      ),
      protocol: protocol,
      metadata: const {}, // LSLStreamInfo doesn't expose metadata directly
      streamType:
          streamInfo.streamType.toString(), // Convert LSLContentType to string
      sourceId: streamInfo.sourceId,
      contentType: streamInfo.streamType, // Use streamType as contentType
      pollingConfig: pollingConfig ?? const LSLPollingConfig(),
      transportConfig: transportConfig ?? const LSLTransportConfig(),
    );
  }

  /// Convert to LSLStreamInfo for creating outlets/inlets
  Future<LSLStreamInfo> toStreamInfo() async {
    return await LSL.createStreamInfo(
      streamName: id,
      streamType: contentType,
      channelCount: channelCount,
      sampleRate: maxSampleRate,
      channelFormat: channelFormat.lslFormat,
      sourceId: sourceId,
    );
  }
}

/// Configuration for user-requested data streams
class LSLDataStreamConfig extends LSLStreamConfig {
  LSLDataStreamConfig({
    LSLPollingConfig? pollingConfig,
    super.channelCount = 8,
    super.maxSampleRate = 250.0,
    super.contentType,
    super.protocol = const ProducerConsumerProtocol(),
    super.metadata = const {'type': 'data'},
    required super.sourceId,
  }) : super(
         id: 'data_stream',
         pollingFrequency: maxSampleRate,
         channelFormat: CoordinatorLSLChannelFormat.float32, // Default format
         pollingConfig:
             pollingConfig ??
             const LSLPollingConfig(
               useBusyWait: false,
               usePollingIsolate: true,
               targetIntervalMicroseconds: 4000, // 250 Hz default
               bufferSize: 500,
               pullTimeout: 0.0,
             ),
       );

  /// High-frequency data streams (EEG, etc.)
  factory LSLDataStreamConfig.highFrequency({
    double targetFrequency = 500.0,
    int channelCount = 32,
    required String sourceId,
  }) {
    return LSLDataStreamConfig(
      pollingConfig: LSLPollingConfig.highFrequency(
        targetFrequency: targetFrequency,
      ),
      channelCount: channelCount,
      maxSampleRate: targetFrequency,
      sourceId: sourceId,
    );
  }

  /// Low-frequency data streams (input events, etc.)
  factory LSLDataStreamConfig.lowFrequency({
    double targetFrequency = 100.0,
    int channelCount = 4,
    required String sourceId,
  }) {
    return LSLDataStreamConfig(
      pollingConfig: LSLPollingConfig.standard(),
      channelCount: channelCount,
      maxSampleRate: targetFrequency,
      contentType: LSLContentType.markers,
      sourceId: sourceId,
    );
  }
}

/// Configuration for LSL polling behavior - extracted from existing high-frequency patterns
class LSLPollingConfig {
  /// Use busy-wait polling instead of timer-based polling
  final bool useBusyWait;

  /// Use separate isolate for the polling loop (level 1 isolation)
  final bool usePollingIsolate;

  /// Use isolated inlets (level 2 isolation - usually not needed with polling isolate)
  final bool useIsolatedInlets;

  /// Use isolated outlets (level 2 isolation - usually not needed with polling isolate)
  final bool useIsolatedOutlets;

  /// Target polling interval in microseconds
  final int targetIntervalMicroseconds;

  /// Buffer size for high-frequency data
  final int bufferSize;

  /// Timeout for individual sample pulls (in seconds)
  final double pullTimeout;

  /// Threshold in microseconds above which we use Future.delayed instead of busy-wait
  /// Below this threshold, we busy-wait for precise timing
  final int busyWaitThresholdMicroseconds;

  const LSLPollingConfig({
    this.useBusyWait = true,
    this.usePollingIsolate = true,
    this.useIsolatedInlets = false,
    this.useIsolatedOutlets = false,
    this.targetIntervalMicroseconds = 1000, // 1000 Hz default
    this.bufferSize = 1000,
    this.pullTimeout = 0.0, // Non-blocking by default
    this.busyWaitThresholdMicroseconds = 100, // Switch to sleep above 100μs
  });

  /// Create config optimized for high-frequency data (based on existing patterns)
  factory LSLPollingConfig.highFrequency({
    double targetFrequency = 1000.0,
    bool useBusyWait = true,
    int bufferSize = 1000,
  }) {
    return LSLPollingConfig(
      useBusyWait: useBusyWait,
      usePollingIsolate: true,
      targetIntervalMicroseconds: (1000000 / targetFrequency).round(),
      bufferSize: bufferSize,
    );
  }

  factory LSLPollingConfig.standard() {
    return const LSLPollingConfig(
      useBusyWait: false,
      usePollingIsolate: true,
      targetIntervalMicroseconds: 10000, // 100 Hz
      bufferSize: 100,
      pullTimeout: 0.0,
    );
  }

  /// Create config for testing/debugging
  factory LSLPollingConfig.testing() {
    return const LSLPollingConfig(
      useBusyWait: false,
      usePollingIsolate: false,
      targetIntervalMicroseconds: 10000, // 100 Hz
      bufferSize: 100,
      pullTimeout: 0.0,
    );
  }

  /// Configuration for coordination streams (restricted DataStream subtype)
  /// Always uses separate isolate to ensure coordination/data separation
  factory LSLPollingConfig.coordination() {
    return const LSLPollingConfig(
      useBusyWait: false,
      usePollingIsolate: true, // Always isolated from data streams
      targetIntervalMicroseconds: 50000, // 20 Hz - coordination frequency
      bufferSize: 50,
      pullTimeout: 0.1, // Small timeout for coordination messages
    );
  }

  /// Configuration for user data streams
  /// Always uses separate isolate from coordination
  factory LSLPollingConfig.dataStream({
    double targetFrequency = 250.0,
    bool useBusyWait = false,
  }) {
    return LSLPollingConfig(
      useBusyWait: useBusyWait,
      usePollingIsolate: true, // Always isolated from coordination
      targetIntervalMicroseconds: (1000000 / targetFrequency).round(),
      bufferSize: (targetFrequency * 2).round(), // 2 seconds of buffer
      pullTimeout: 0.0, // Non-blocking for data streams
    );
  }
}

/// Configuration for LSL transport layer
class LSLTransportConfig {
  /// Maximum buffer size for outlets
  final int maxOutletBuffer;

  /// Chunk size for outlet operations
  final int outletChunkSize;

  /// Maximum buffer size for inlets
  final int maxInletBuffer;

  /// Chunk size for inlet operations
  final int inletChunkSize;

  /// Whether to enable recovery for inlets
  final bool enableRecovery;

  /// Stream resolver configuration
  final LSLResolverConfig resolverConfig;

  const LSLTransportConfig({
    this.maxOutletBuffer = 360,
    this.outletChunkSize = 0,
    this.maxInletBuffer = 360,
    this.inletChunkSize = 0,
    this.enableRecovery = true,
    this.resolverConfig = const LSLResolverConfig(),
  });
}

/// Configuration for LSL stream resolvers (predicate-based only)
// class LSLResolverConfig {
//   /// Maximum number of streams to resolve
//   final int maxStreams;

//   /// How long to remember streams after they disappear (seconds)
//   final double forgetAfter;

//   /// Timeout for stream resolution (seconds)
//   final double resolveTimeout;

//   /// Custom additional predicate for stream filtering
//   final String? customPredicate;

//   const LSLResolverConfig({
//     this.maxStreams = 50,
//     this.forgetAfter = 5.0,
//     this.resolveTimeout = 5.0,
//     this.customPredicate,
//   });

//   /// Generate predicate for coordination streams (based on existing patterns)
//   String coordinationPredicate(String streamName) {
//     final basePredicate =
//         "name='$streamName' and starts-with(source_id, 'coord_')";
//     return customPredicate != null
//         ? '$basePredicate and ($customPredicate)'
//         : basePredicate;
//   }

//   /// Generate predicate for data streams with optional metadata filtering
//   String dataPredicate(
//     String streamName, {
//     Map<String, String>? metadataFilters,
//   }) {
//     var predicate = "name='$streamName'";

//     if (metadataFilters != null && metadataFilters.isNotEmpty) {
//       for (final entry in metadataFilters.entries) {
//         predicate += " and ${entry.key}='${entry.value}'";
//       }
//     }

//     return customPredicate != null
//         ? '$predicate and ($customPredicate)'
//         : predicate;
//   }

//   /// Generate predicate for stream type filtering
//   String streamTypePredicate(String streamType) {
//     final basePredicate = "type='$streamType'";
//     return customPredicate != null
//         ? '$basePredicate and ($customPredicate)'
//         : basePredicate;
//   }
// }
