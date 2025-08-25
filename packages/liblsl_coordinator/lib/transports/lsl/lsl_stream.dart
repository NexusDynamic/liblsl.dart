import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

extension LSLType on StreamDataType {
  /// Converts a [StreamDataType] to the corresponding LSL channel format.
  LSLChannelFormat toLSLChannelFormat() {
    switch (this) {
      case StreamDataType.int8:
        LSLChannelFormat.int8;
      case StreamDataType.int16:
        return LSLChannelFormat.int16;
      case StreamDataType.int32:
        return LSLChannelFormat.int32;
      case StreamDataType.int64:
        return LSLChannelFormat.int64;
      case StreamDataType.float32:
        return LSLChannelFormat.float32;
      case StreamDataType.double64:
        return LSLChannelFormat.double64;
      case StreamDataType.string:
        return LSLChannelFormat.string;
    }
    throw UnsupportedError('Unsupported StreamDataType: $this');
  }
}

/// Helper class with static methods for working with LSL StreamInfo
/// Especially a unified way of working with the metadata, or standardized
/// stream names for discovery.
class LSLStreamInfoHelper {
  static const String streamNameKey = 'stream_name';
  static const String sessionNameKey = 'session';
  static const String nodeIdKey = 'node_id';
  static const String nodeRoleKey = 'node_role';
  static const String nodeCapabilitiesKey = 'node_capabilities';

  /// Generates a standardized stream name for a given stream configuration
  /// and node information.
  static String generateStreamName(
    NetworkStreamConfig config, {
    required Node node,
  }) {
    return '${config.name}-${node.id}-${node.getMetadata('role', defaultValue: 'none')}';
  }

  static Map<String, String> parseStreamName(String name) {
    final parts = name.split('-');
    if (parts.length < 3) {
      throw FormatException('Invalid stream name format: $name');
    }
    return {
      streamNameKey: parts.sublist(0, parts.length - 2).join('-'),
      nodeIdKey: parts[parts.length - 2],
      nodeRoleKey: parts[parts.length - 1],
    };
  }

  /// Create a stream info (for use in an outlet) from the given parameters.
  static Future<LSLStreamInfo> createStreamInfo({
    required NetworkStreamConfig config,
    required CoordinationSessionConfig sessionConfig,
    required Node node,
  }) async {
    final streamName = generateStreamName(config, node: node);

    final LSLStreamInfoWithMetadata info = await LSL.createStreamInfo(
      streamName: streamName,
      streamType: LSLContentType.markers,
      channelCount: config.channels,
      channelFormat: config.dataType.toLSLChannelFormat(),
      sampleRate: config.sampleRate,
    );

    // Add standard metadata
    final LSLDescription infoMetadata = info.description;
    final LSLXmlNode rootElement = infoMetadata.value;
    rootElement.addChildValue(sessionNameKey, sessionConfig.name);
    rootElement.addChildValue(nodeIdKey, node.id);
    rootElement.addChildValue(
      nodeRoleKey,
      node.getMetadata('role', defaultValue: 'none'),
    );
    rootElement.addChildValue(
      nodeCapabilitiesKey,
      (node.capabilities.join(',')),
    );

    return info;
  }

  /// Parses standard metadata from the given [LSLStreamInfoWithMetadata].
  static Map<String, String> parseMetadata(LSLStreamInfoWithMetadata info) {
    final Map<String, String> metadata = {};
    final LSLDescription description = info.description;
    final LSLXmlNode rootElement = description.value;
    for (final child in rootElement.children) {
      if (!child.isText()) continue;
      try {
        metadata[child.name] = child.textValue;
      } catch (e) {
        // ignore malformed metadata entries
        logger.warning('Failed to parse metadata entry ${child.name}: $e');
        continue;
      }
    }
    return metadata;
  }

  /// Generates an LSL stream resolver predicate based on the given parameters.
  /// Any parameter that is null is ignored in the predicate.
  /// For example, to find streams with a specific name prefix and session name:
  /// ```dart
  /// final predicate = LSLStreamInfoHelper.generatePredicate(
  ///   streamNamePrefix: 'mystream',
  ///   sessionName: 'mysession',
  /// );```
  /// This would generate a predicate like:
  /// "starts-with(name, 'mystream') and //info/desc/session='mysession'"
  /// which can be used with [LSLStreamResolverContinuousByPredicate].
  static String generatePredicate({
    String? streamNamePrefix,
    String? streamNameSuffix,
    String? sessionName,
    String? nodeId,
    String? nodeRole,
    String? nodeCapabilities,
    String? sourceIdPrefix,
    String? sourceIdSuffix,
  }) {
    final List<String> conditions = [];
    if (streamNamePrefix != null) {
      conditions.add("starts-with(name, '$streamNamePrefix')");
    }
    if (streamNameSuffix != null) {
      conditions.add("ends-with(name, '$streamNameSuffix')");
    }
    if (sourceIdPrefix != null) {
      conditions.add("starts-with(source_id, '$sourceIdPrefix')");
    }
    if (sourceIdSuffix != null) {
      conditions.add("ends-with(source_id, '$sourceIdSuffix')");
    }
    if (sessionName != null) {
      conditions.add("//info/desc/$sessionName='$sessionName'");
    }
    if (nodeId != null) {
      conditions.add("//info/desc/$nodeId='$nodeId'");
    }
    if (nodeRole != null) {
      conditions.add("//info/desc/$nodeRole='$nodeRole'");
    }
    if (nodeCapabilities != null) {
      conditions.add("//info/desc/$nodeCapabilities='$nodeCapabilities'");
    }
    if (conditions.isEmpty) {
      throw ArgumentError('At least one parameter must be provided');
    }
    return conditions.join(' and ');
  }

  /// f
}

/// Factory for creating LSL-based network streams.
class LSLNetworkStreamFactory extends NetworkStreamFactory {
  @override
  Future<DataStream> createDataStream(
    NetworkStreamConfig config, {
    List<Node>? producers,
    List<Node>? consumers,
  }) async {
    // Create and return an LSL stream with the given configuration.
    throw UnimplementedError();
  }

  @override
  Future<LSLCoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config, {
    List<Node>? producers,
    List<Node>? consumers,
  }) async {
    // Create and return an LSL coordination stream with the given configuration.
    throw UnimplementedError();
  }
}

class LSLCoordinationStream extends CoordinationStream {
  /// The transport configuration used for this coordination stream.
  late final LSLTransportConfig transportConfig;

  LSLCoordinationStream(super.config) {
    if (config.transportConfig is! LSLTransportConfig) {
      logger.warning(
        'LSLCoordinationStream requires LSLTransportConfig, '
        ' but got ${config.transportConfig.runtimeType}. '
        'Using default LSLTransportConfig.',
      );
      transportConfig = LSLTransportConfigFactory().defaultConfig();
    } else {
      transportConfig = config.transportConfig as LSLTransportConfig;
    }
  }

  @override
  FutureOr<void> sendMessage(Message message) {
    // Implement sending a message via LSL here.
    throw UnimplementedError();
  }

  @override
  FutureOr<void> create() {
    // TODO: implement create
    throw UnimplementedError();
  }

  @override
  // TODO: implement created
  bool get created => throw UnimplementedError();

  @override
  // TODO: implement description
  String? get description => throw UnimplementedError();

  @override
  FutureOr<void> dispose() {
    // TODO: implement dispose
    throw UnimplementedError();
  }

  @override
  // TODO: implement disposed
  bool get disposed => throw UnimplementedError();

  @override
  // TODO: implement inbox
  Stream<StringMessage> get inbox => throw UnimplementedError();

  @override
  // TODO: implement manager
  IResourceManager? get manager => throw UnimplementedError();

  @override
  // TODO: implement outbox
  StreamSink<StringMessage> get outbox => throw UnimplementedError();

  @override
  // TODO: implement uId
  String get uId => throw UnimplementedError();

  @override
  FutureOr<void> updateManager(IResourceManager? newManager) {
    // TODO: implement updateManager
    throw UnimplementedError();
  }
}
