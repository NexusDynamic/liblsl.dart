import 'dart:async';
import 'dart:isolate';
import 'package:liblsl/lsl.dart';

import '../core/coordination_node.dart';
import '../core/stream_layer_config.dart';
import '../core/multi_layer_coordinator.dart';

/// Manages a single stream layer with outlets and inlets
class StreamLayerManager {
  final String layerId;
  final String nodeId;
  final StreamLayerConfig layerConfig;
  final bool isCoordinator;
  final bool receiveOwnMessages;
  List<NetworkNode> knownNodes;

  final StreamController<LayerDataEvent> _dataController =
      StreamController.broadcast();
  final StreamController<CoordinationEvent> _eventController =
      StreamController.broadcast();

  LSLOutlet? _outlet;
  final Map<String, LSLInlet> _inlets = {};
  final Map<String, StreamController<List<dynamic>>> _inletControllers = {};

  Isolate? _outletIsolate;
  Isolate? _inletIsolate;

  ReceivePort? _outletReceivePort;
  ReceivePort? _inletReceivePort;
  SendPort? _outletSendPort;
  SendPort? _inletSendPort;

  bool _isInitialized = false;
  bool _inletsPaused = false;

  /// Whether this manager is initialized
  bool get isInitialized => _isInitialized;

  StreamLayerManager({
    required this.layerId,
    required this.nodeId,
    required this.layerConfig,
    required this.isCoordinator,
    required this.knownNodes,
    this.receiveOwnMessages = true,
  });

  /// Stream of data events from this layer
  Stream<LayerDataEvent> get dataStream => _dataController.stream;

  /// Stream of coordination events from this layer
  Stream<CoordinationEvent> get eventStream => _eventController.stream;

  /// Whether the inlets are currently paused
  bool get inletsPaused => _inletsPaused;

  /// Initialize the layer manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Create outlet if required
    if (layerConfig.requiresOutlet) {
      await _createOutlet();
    }

    // Create inlets based on requirements
    if (layerConfig.requiresInletFromAll) {
      await _createInlets();
    } else if (isCoordinator && layerConfig.coordinatorRequiresInletFromAll) {
      // Coordinator gets inlets from all participants
      await _createInlets();
    }

    _isInitialized = true;
  }

  /// Update known nodes and adjust inlets accordingly
  void updateKnownNodes(List<NetworkNode> nodes) {
    knownNodes = nodes;

    // Update inlets if already initialized
    if (_isInitialized) {
      unawaited(_updateInlets());
    }
  }

  /// Send data through the outlet
  Future<void> sendData(List<dynamic> data) async {
    if (_outlet == null) {
      throw StateError('Outlet not initialized for layer $layerId');
    }

    if (layerConfig.useIsolate && _outletSendPort != null) {
      _outletSendPort!.send({'action': 'send_data', 'data': data});
    } else {
      await _outlet!.pushSample(data);
    }
  }

  /// Pause inlet data collection
  Future<void> pauseInlets() async {
    if (!layerConfig.isPausable) {
      throw StateError('Layer $layerId is not pausable');
    }

    _inletsPaused = true;

    if (layerConfig.useIsolate && _inletSendPort != null) {
      _inletSendPort!.send({'action': 'pause_inlets'});
    } else {
      // For non-isolate mode, we'll implement pause logic in the polling loop
    }
  }

  /// Resume inlet data collection
  Future<void> resumeInlets() async {
    if (!layerConfig.isPausable) {
      throw StateError('Layer $layerId is not pausable');
    }

    _inletsPaused = false;

    if (layerConfig.useIsolate && _inletSendPort != null) {
      _inletSendPort!.send({'action': 'resume_inlets'});
    } else {
      // For non-isolate mode, the polling loop will resume automatically
    }
  }

  /// Create outlet for this layer
  Future<void> _createOutlet() async {
    final streamInfo = await LSL.createStreamInfo(
      streamName: layerConfig.streamConfig.streamName,
      streamType: layerConfig.streamConfig.streamType,
      channelCount: layerConfig.streamConfig.channelCount,
      sampleRate: layerConfig.streamConfig.sampleRate,
      channelFormat: layerConfig.streamConfig.channelFormat,
      sourceId: '${layerId}_$nodeId',
    );

    _outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: layerConfig.streamConfig.chunkSize,
      maxBuffer: layerConfig.streamConfig.maxBuffer,
      useIsolates: layerConfig.streamConfig.isolateOutlet,
    );
  }

  /// Create inlets for this layer
  Future<void> _createInlets() async {
    await _discoverAndCreateInlets();

    // Disable isolate creation for now
    // if (layerConfig.useIsolate) {
    //   await _createInletIsolate();
    // } else {
    _startInletPolling();
    // }
  }

  /// Update inlets when nodes change
  Future<void> _updateInlets() async {
    print(
      '[StreamLayerManager] $layerId: _updateInlets called - knownNodes: ${knownNodes.map((n) => n.nodeId).toList()}, receiveOwnMessages: $receiveOwnMessages',
    );

    // Close existing inlets that are no longer needed
    final currentInletKeys = _inlets.keys.toSet();
    final requiredInletKeys =
        knownNodes
            .where((node) {
              final shouldReceive = receiveOwnMessages || node.nodeId != nodeId;
              print(
                '[StreamLayerManager] $layerId: Node ${node.nodeId} - shouldReceive: $shouldReceive (receiveOwnMessages: $receiveOwnMessages, isOwnNode: ${node.nodeId == nodeId})',
              );
              return shouldReceive;
            }) // Only create inlet for self if receiveOwnMessages is true
            .map((node) => '${layerId}_${node.nodeId}')
            .toSet();

    print(
      '[StreamLayerManager] $layerId: Current inlets: $currentInletKeys, Required inlets: $requiredInletKeys',
    );

    // Remove inlets for nodes that left
    final toRemove = currentInletKeys.difference(requiredInletKeys);
    print('[StreamLayerManager] $layerId: Removing inlets for: $toRemove');
    for (final key in toRemove) {
      final inlet = _inlets.remove(key);
      await inlet?.destroy();
      // inlet?.streamInfo.destroy();
      _inletControllers.remove(key)?.close();
    }

    // Add inlets for new nodes
    final toAdd = requiredInletKeys.difference(currentInletKeys);
    print('[StreamLayerManager] $layerId: Adding inlets for: $toAdd');
    for (final key in toAdd) {
      await _createInletForSourceId(key);
    }

    // Update isolate with new inlets
    if (layerConfig.useIsolate && _inletSendPort != null) {
      _inletSendPort!.send({
        'action': 'update_inlets',
        'inlets': _inlets.keys.toList(),
      });
    }
  }

  /// Discover and create inlets for available streams
  Future<void> _discoverAndCreateInlets() async {
    print(
      '[StreamLayerManager] $layerId: _discoverAndCreateInlets called - isCoordinator: $isCoordinator, knownNodes.length: ${knownNodes.length}, receiveOwnMessages: $receiveOwnMessages',
    );

    // If we're a coordinator with no other nodes, check if we should still create inlet for own messages
    if (isCoordinator && knownNodes.length <= 1) {
      print(
        '[StreamLayerManager] $layerId: Single coordinator case - checking receiveOwnMessages: $receiveOwnMessages',
      );
      if (!receiveOwnMessages) {
        print(
          '[StreamLayerManager] $layerId: Skipping inlet discovery - no other nodes and receiveOwnMessages=false',
        );
        return;
      } else {
        print(
          '[StreamLayerManager] $layerId: Continuing with inlet discovery despite single coordinator - receiveOwnMessages=true',
        );
      }
    }

    final streams = await LSL.resolveStreamsByPredicate(
      predicate:
          "name='${layerConfig.streamConfig.streamName}' and starts-with(source_id, '${layerId}_')",
      waitTime: 1.0,
      maxStreams: 50,
    );

    print(
      '[StreamLayerManager] $layerId: Found ${streams.length} streams matching predicate',
    );
    for (final stream in streams) {
      print(
        '[StreamLayerManager] $layerId: Stream found - name: ${stream.streamName}, sourceId: ${stream.sourceId}, type: ${stream.streamType}',
      );
    }

    final layerStreams = streams.where((stream) {
      final typeMatch =
          stream.streamType == layerConfig.streamConfig.streamType;
      final isOwnStream = stream.sourceId == '${layerId}_$nodeId';
      final shouldReceive = receiveOwnMessages || !isOwnStream;
      print(
        '[StreamLayerManager] $layerId: Stream ${stream.sourceId} - typeMatch: $typeMatch, isOwnStream: $isOwnStream, shouldReceive: $shouldReceive',
      );
      return typeMatch && shouldReceive;
    });

    // get reamining streams that are not in layerStreams
    final remainingStreams =
        streams
            .where(
              (stream) =>
                  !layerStreams.any((ls) => ls.sourceId == stream.sourceId),
            )
            .toList();
    remainingStreams.destroy();

    final layerStreamsList = layerStreams.toList();
    print(
      '[StreamLayerManager] $layerId: Creating inlets for ${layerStreamsList.length} streams',
    );
    for (final streamInfo in layerStreamsList) {
      print(
        '[StreamLayerManager] $layerId: Creating inlet for sourceId: ${streamInfo.sourceId}',
      );
      await _createInletForStreamInfo(streamInfo);
    }
  }

  Future<void> _createInletForStreamInfo(LSLStreamInfo streamInfo) async {
    final inlet = await LSL.createInlet(
      streamInfo: streamInfo,
      maxBuffer: layerConfig.streamConfig.maxBuffer,
      chunkSize: layerConfig.streamConfig.chunkSize,
      recover: true,
      useIsolates:
          layerConfig
              .streamConfig
              .isolateInlet, // Disable isolates for now to avoid FFI issues
    );

    _inlets[streamInfo.sourceId] = inlet;
    _inletControllers[streamInfo.sourceId] =
        StreamController<List<dynamic>>.broadcast();

    print(
      '[StreamLayerManager] $layerId: Successfully created inlet for sourceId: ${streamInfo.sourceId} - Total inlets: ${_inlets.length}',
    );
  }

  /// Create inlet for a specific source ID
  Future<void> _createInletForSourceId(String sourceId) async {
    if (_inlets.containsKey(sourceId)) {
      print(
        '[StreamLayerManager] $layerId: Inlet for $sourceId already exists, skipping',
      );
      return;
    }

    print(
      '[StreamLayerManager] $layerId: Creating inlet for sourceId: $sourceId',
    );

    final streams = await LSL.resolveStreamsByProperty(
      property: LSLStreamProperty.sourceId,
      value: sourceId,
      waitTime: 1.0,
      maxStreams: 1,
    );

    final streamInfo = streams.firstOrNull;

    if (streamInfo == null) {
      // Stream not found yet - this is normal during initial setup
      // when other nodes haven't created their outlets yet
      print(
        '[StreamLayerManager] $layerId: Stream for sourceId $sourceId not found yet, skipping inlet creation',
      );
      return;
    }

    print(
      '[StreamLayerManager] $layerId: Found stream for sourceId $sourceId, creating inlet',
    );
    await _createInletForStreamInfo(streamInfo);
  }

  /// Start polling inlets (non-isolate mode)
  void _startInletPolling() {
    Timer.periodic(const Duration(milliseconds: 10), (timer) async {
      if (!_isInitialized) {
        timer.cancel();
        return;
      }

      if (_inletsPaused) return;

      for (final entry in _inlets.entries) {
        final sourceId = entry.key;
        final inlet = entry.value;

        try {
          final sample = await inlet.pullSample();
          if (sample.isNotEmpty) {
            final sourceNodeId = sourceId.replaceFirst('${layerId}_', '');

            _dataController.add(
              LayerDataEvent(
                layerId: layerId,
                sourceNodeId: sourceNodeId,
                data: sample.data,
                timestamp: DateTime.now(),
              ),
            );
          }
        } catch (e) {
          print('Error polling inlet $sourceId: $e');
        }
      }
    });
  }

  /// Dispose the layer manager
  Future<void> dispose() async {
    _isInitialized = false;

    _outletIsolate?.kill();
    _inletIsolate?.kill();

    _outletReceivePort?.close();
    _inletReceivePort?.close();

    for (final inlet in _inlets.values) {
      await inlet.destroy();
      // inlet.streamInfo.destroy();
    }
    _inlets.clear();

    for (final controller in _inletControllers.values) {
      await controller.close();
    }
    _inletControllers.clear();

    await _outlet?.destroy();
    // _outlet?.streamInfo.destroy();

    if (!_dataController.isClosed) {
      await _dataController.close();
    }

    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }
}
