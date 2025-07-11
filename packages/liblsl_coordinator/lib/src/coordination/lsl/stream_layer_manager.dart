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
    } else if (isCoordinator) {
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
      _outlet!.pushSampleSync(data);
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
      useIsolates: false, // Disable isolates for now to avoid FFI issues
    );

    // Disable isolate creation for now
    // if (layerConfig.useIsolate) {
    //   await _createOutletIsolate();
    // }
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
    // Close existing inlets that are no longer needed
    final currentInletKeys = _inlets.keys.toSet();
    final requiredInletKeys =
        knownNodes
            .where(
              (node) => node.nodeId != nodeId,
            ) // Don't create inlet for self
            .map((node) => '${layerId}_${node.nodeId}')
            .toSet();

    // Remove inlets for nodes that left
    for (final key in currentInletKeys.difference(requiredInletKeys)) {
      final inlet = _inlets.remove(key);
      inlet?.destroy();
      _inletControllers.remove(key)?.close();
    }

    // Add inlets for new nodes
    for (final key in requiredInletKeys.difference(currentInletKeys)) {
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
    // If we're a coordinator with no other nodes, skip inlet discovery
    if (isCoordinator && knownNodes.length <= 1) {
      return;
    }

    final streams = await LSL.resolveStreams(
      waitTime: 0.5, // Reduce wait time to avoid hanging
      maxStreams: 50,
    );

    final layerStreams = streams.where(
      (stream) =>
          stream.streamName == layerConfig.streamConfig.streamName &&
          stream.streamType == layerConfig.streamConfig.streamType &&
          stream.sourceId !=
              '${layerId}_$nodeId' && // Don't create inlet for self
          stream.sourceId.startsWith('${layerId}_'),
    );

    for (final streamInfo in layerStreams) {
      await _createInletForSourceId(streamInfo.sourceId);
    }
  }

  /// Create inlet for a specific source ID
  Future<void> _createInletForSourceId(String sourceId) async {
    if (_inlets.containsKey(sourceId)) return;

    final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 1);

    final streamInfo =
        streams.where((stream) => stream.sourceId == sourceId).firstOrNull;

    if (streamInfo == null) {
      // Stream not found yet - this is normal during initial setup
      // when other nodes haven't created their outlets yet
      return;
    }

    final inlet = await LSL.createInlet(
      streamInfo: streamInfo,
      maxBuffer: layerConfig.streamConfig.maxBuffer,
      chunkSize: layerConfig.streamConfig.chunkSize,
      recover: true,
      useIsolates: false, // Disable isolates for now to avoid FFI issues
    );

    _inlets[sourceId] = inlet;
    _inletControllers[sourceId] = StreamController<List<dynamic>>.broadcast();
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
          final sample = inlet.pullSampleSync();
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
      inlet.destroy();
    }
    _inlets.clear();

    for (final controller in _inletControllers.values) {
      await controller.close();
    }
    _inletControllers.clear();

    _outlet?.destroy();

    if (!_dataController.isClosed) {
      await _dataController.close();
    }

    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }
}
