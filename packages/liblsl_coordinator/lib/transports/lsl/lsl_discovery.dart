import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl/lsl_coordination.dart';
import 'package:synchronized/synchronized.dart';

/// LSL-based discovery mechanism for network nodes for a given stream
/// layer.
class LslDiscovery extends LSLResource implements IPausable {
  /// Configuration for coordination
  final NetworkStreamConfig streamConfig;
  final CoordinationConfig coordinationConfig;

  final bool _paused = false;
  @override
  bool get paused => _paused;

  Timer? _discoveryInterval;
  final Lock _discoveryLock = Lock();

  List<LSLStreamInfo> _discoveredStreams = [];

  LslDiscovery({
    required this.streamConfig,
    required this.coordinationConfig,
    required super.id,
    super.manager,
  });

  late final LSLStreamResolverContinuous _resolver;

  @override
  String get id => 'lsl-discovery-${streamConfig.id}';

  /// Ensures that the resource is created before performing operations.
  void _ensureCreated() {
    if (!created || disposed) {
      throw StateError('Discovery resource is not created');
    }
  }

  @override
  Future<void> create() async {
    // Initialize LSL discovery mechanisms here.
    await super.create();
    _resolver = LSLStreamResolverContinuousByPredicate(
      // @TODO: generate predicate using [LSLStreamInfoHelper]
      predicate:
          "starts-with(name, '${streamConfig.name}') and //info/desc/session='${coordinationConfig.sessionConfig.name}'",
      maxStreams: coordinationConfig.topologyConfig.maxNodes,
      forgetAfter:
          coordinationConfig.sessionConfig.nodeTimeout.inMilliseconds / 1000.0,
    );
    _resolver.create();
    _startDiscovery();
  }

  /// Starts the discovery process with the configured interval.
  void _startDiscovery() {
    _ensureCreated();
    _discoveryInterval?.cancel();
    _discoveryInterval = Timer.periodic(
      coordinationConfig.sessionConfig.discoveryInterval,
      (timer) async {
        await _discover();
      },
    );
  }

  void _stopDiscovery() {
    _discoveryInterval?.cancel();
    _discoveryInterval = null;
  }

  @override
  void pause() {
    _ensureCreated();
    if (paused) {
      return;
    }
    _stopDiscovery();
  }

  @override
  void resume() {
    _ensureCreated();
    if (!paused) {
      return;
    }
    _startDiscovery();
  }

  /// Retrieves the list of discovered LSL streams.
  Future<void> _discover() async {
    if (paused) {
      return;
    }
    return _discoveryLock.synchronized(() async {
      if (disposed) {
        throw StateError('Cannot discover streams: Resource is disposed');
      }
      if (!created) {
        throw StateError('Cannot discover streams: Resource is not created');
      }

      // clear the buffer first
      _discoveredStreams.destroy();
      _discoveredStreams.clear();

      _discoveredStreams = await _resolver.resolve();
    });
  }

  @override
  Future<void> dispose() async {
    // Clean up LSL discovery mechanisms here.
    _stopDiscovery();
    _resolver.destroy();
    await _discoveryLock.synchronized(() async {
      // Ensure no discovery is in progress
      _discoveredStreams.destroy();
      _discoveredStreams.clear();
    });

    await super.dispose();
  }
}
