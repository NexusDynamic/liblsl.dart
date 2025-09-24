import 'package:liblsl_coordinator/framework.dart';
import 'package:collection/collection.dart';

/// Meta config collection for the whole library.
class CoordinationConfig implements IConfig {
  /// The name of the coordination configuration.
  @override
  final String name;

  @override
  String get id => 'coordination-${hashCode.toString()}';

  @override
  String? get description => 'Configuration for coordination $name (id: $id)';

  late final CoordinationSessionConfig sessionConfig;
  late final CoordinationStreamConfig streamConfig;
  // can be created later from the session
  final List<NetworkStreamConfig>? initialStreamConfigs;
  final TopologyConfig topologyConfig;
  final ITransportConfig transportConfig;

  CoordinationConfig({
    this.name = 'liblsl_coordinator',
    CoordinationSessionConfig? sessionConfig,
    CoordinationStreamConfig? streamConfig,
    this.initialStreamConfigs,
    TopologyConfig? topologyConfig,
    required this.transportConfig,
  }) : sessionConfig =
           sessionConfig ?? CoordinationSessionConfigFactory().defaultConfig(),
       streamConfig =
           streamConfig ?? CoordinationStreamConfigFactory().defaultConfig(),
       topologyConfig =
           topologyConfig ??
           HierarchicalTopologyConfigFactory().defaultConfig() {
    validate(throwOnError: true);
  }

  @override
  bool validate({bool throwOnError = false}) {
    if (name.isEmpty) {
      if (throwOnError) {
        throw ArgumentError('Configuration name cannot be empty');
      }
      return false;
    }
    if (!sessionConfig.validate(throwOnError: throwOnError)) {
      if (throwOnError) {
        throw ArgumentError('Invalid session configuration');
      }
      return false;
    }
    if (!streamConfig.validate(throwOnError: throwOnError)) {
      if (throwOnError) {
        throw ArgumentError('Invalid stream configuration');
      }
      return false;
    }
    if (!topologyConfig.validate(throwOnError: throwOnError)) {
      if (throwOnError) {
        throw ArgumentError('Invalid topology configuration');
      }
      return false;
    }
    if (!transportConfig.validate(throwOnError: throwOnError)) {
      if (throwOnError) {
        throw ArgumentError('Invalid transport configuration');
      }
      return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'sessionConfig': sessionConfig.toMap(),
      'streamConfig': streamConfig.toMap(),
      'initialStreamConfigs': initialStreamConfigs
          ?.map((e) => e.toMap())
          .toList(),
      'topologyConfig': topologyConfig.toMap(),
      'transportConfig': transportConfig.toMap(),
    };
  }

  @override
  CoordinationConfig copyWith({
    String? name,
    CoordinationSessionConfig? sessionConfig,
    CoordinationStreamConfig? streamConfig,
    List<NetworkStreamConfig>? initialStreamConfigs,
    TopologyConfig? topologyConfig,
    ITransportConfig? transportConfig,
  }) {
    return CoordinationConfig(
      name: name ?? this.name,
      sessionConfig: sessionConfig ?? this.sessionConfig,
      streamConfig: streamConfig ?? this.streamConfig,
      initialStreamConfigs: initialStreamConfigs ?? this.initialStreamConfigs,
      topologyConfig: topologyConfig ?? this.topologyConfig,
      transportConfig: transportConfig ?? this.transportConfig,
    );
  }

  @override
  String toString() {
    return 'CoordinationConfig(name: $name, sessionConfig: $sessionConfig, streamConfig: $streamConfig, initialStreamConfigs: $initialStreamConfigs, topologyConfig: $topologyConfig, transportConfig: $transportConfig)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CoordinationConfig &&
        other.runtimeType == runtimeType &&
        other.name == name &&
        other.sessionConfig == sessionConfig &&
        other.streamConfig == streamConfig &&
        ((initialStreamConfigs == null && other.initialStreamConfigs == null) ||
            (initialStreamConfigs != null &&
                other.initialStreamConfigs != null &&
                initialStreamConfigs!.equals(other.initialStreamConfigs!))) &&
        other.topologyConfig == topologyConfig &&
        other.transportConfig == transportConfig;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        sessionConfig.hashCode ^
        streamConfig.hashCode ^
        (initialStreamConfigs?.hashCode ?? 0) ^
        topologyConfig.hashCode ^
        transportConfig.hashCode;
  }
}

/// @TODO: this needs to be implemented, but it should be done in wrapped
/// version that will by default use LSL if LSL is available (but without)
/// requiring it to be imported to avoid breaking on web builds.
// class CoordinationConfigFactory implements IConfigFactory<CoordinationConfig> {
//   @override
//   CoordinationConfig defaultConfig() {
//     return CoordinationConfig(
//       streamConfig: CoordinationStreamConfigFactory().defaultConfig(),
//       sessionConfig: CoordinationSessionConfigFactory().defaultConfig(),
//       topologyConfig: HierarchicalTopologyConfigFactory().defaultConfig(),
//     );
//   }
// }
