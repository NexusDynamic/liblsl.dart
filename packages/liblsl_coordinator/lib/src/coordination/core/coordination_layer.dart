import 'dart:async';

import 'coordination_node.dart';
import 'stream_layer_config.dart';
import 'multi_layer_coordinator.dart';
import '../lsl/stream_layer_manager.dart';

/// Unified interface for coordination layers
abstract class CoordinationLayer {
  /// Unique identifier for this layer
  String get layerId;

  /// Human-readable name for this layer
  String get layerName;

  /// Configuration for this layer
  StreamLayerConfig get config;

  /// Whether this layer is currently active
  bool get isActive;

  /// Whether this layer is currently paused (if pausable)
  bool get isPaused;

  /// Stream of data events from this layer
  Stream<LayerDataEvent> get dataStream;

  /// Stream of layer-specific events
  Stream<CoordinationEvent> get eventStream;

  /// Initialize the layer
  Future<void> initialize();

  /// Start the layer operations
  Future<void> start();

  /// Stop the layer operations
  Future<void> stop();

  /// Send data through this layer's outlet
  Future<void> sendData(List<dynamic> data);

  /// Pause this layer's inlets (only if layer is pausable)
  Future<void> pause();

  /// Resume this layer's inlets (only if layer was paused)
  Future<void> resume();

  /// Update known nodes for this layer
  void updateKnownNodes(List<NetworkNode> nodes);

  /// Dispose the layer resources
  Future<void> dispose();
}

/// Implementation of the coordination layer interface
class CoordinationLayerImpl extends CoordinationLayer {
  final String _layerId;
  final StreamLayerConfig _config;
  final StreamLayerManager _manager;

  CoordinationLayerImpl({
    required String layerId,
    required StreamLayerConfig config,
    required StreamLayerManager manager,
  }) : _layerId = layerId,
       _config = config,
       _manager = manager;

  @override
  String get layerId => _layerId;

  @override
  String get layerName => _config.layerName;

  @override
  StreamLayerConfig get config => _config;

  @override
  bool get isActive => _manager.isInitialized;

  @override
  bool get isPaused => _manager.inletsPaused;

  @override
  Stream<LayerDataEvent> get dataStream => _manager.dataStream;

  @override
  Stream<CoordinationEvent> get eventStream => _manager.eventStream;

  @override
  Future<void> initialize() async {
    await _manager.initialize();
  }

  @override
  Future<void> start() async {
    // Layer starts automatically when initialized
    // This can be extended for more complex start logic
  }

  @override
  Future<void> stop() async {
    // For now, stopping means disposing
    // This can be extended to support pause/stop without dispose
  }

  @override
  Future<void> sendData(List<dynamic> data) async {
    if (!_config.requiresOutlet) {
      throw StateError('Layer $_layerId does not support sending data');
    }
    await _manager.sendData(data);
  }

  @override
  Future<void> pause() async {
    if (!_config.isPausable) {
      throw StateError('Layer $_layerId is not pausable');
    }
    await _manager.pauseInlets();
  }

  @override
  Future<void> resume() async {
    if (!_config.isPausable) {
      throw StateError('Layer $_layerId is not pausable');
    }
    await _manager.resumeInlets();
  }

  @override
  void updateKnownNodes(List<NetworkNode> nodes) {
    _manager.updateKnownNodes(nodes);
  }

  @override
  Future<void> dispose() async {
    await _manager.dispose();
  }
}

/// Collection of coordination layers with convenient access methods
class LayerCollection {
  final Map<String, CoordinationLayer> _layers = {};

  /// Get all layer IDs
  List<String> get layerIds => _layers.keys.toList();

  /// Get all layers
  List<CoordinationLayer> get all => _layers.values.toList();

  /// Get all active layers
  List<CoordinationLayer> get active =>
      _layers.values.where((layer) => layer.isActive).toList();

  /// Get all pausable layers
  List<CoordinationLayer> get pausable =>
      _layers.values.where((layer) => layer.config.isPausable).toList();

  /// Get all paused layers
  List<CoordinationLayer> get paused =>
      _layers.values.where((layer) => layer.isPaused).toList();

  /// Get layers by priority
  List<CoordinationLayer> getByPriority(LayerPriority priority) =>
      _layers.values
          .where((layer) => layer.config.priority == priority)
          .toList();

  /// Add a layer to the collection
  void add(CoordinationLayer layer) {
    _layers[layer.layerId] = layer;
  }

  /// Remove a layer from the collection
  CoordinationLayer? remove(String layerId) {
    return _layers.remove(layerId);
  }

  /// Get a layer by ID
  CoordinationLayer? operator [](String layerId) => _layers[layerId];

  /// Check if a layer exists
  bool contains(String layerId) => _layers.containsKey(layerId);

  /// Get the number of layers
  int get length => _layers.length;

  /// Check if collection is empty
  bool get isEmpty => _layers.isEmpty;

  /// Check if collection is not empty
  bool get isNotEmpty => _layers.isNotEmpty;

  /// Iterate over layers
  Iterable<CoordinationLayer> get values => _layers.values;

  /// Clear all layers
  void clear() {
    _layers.clear();
  }

  /// Pause all pausable layers
  Future<void> pauseAll() async {
    final pausableLayers = pausable;
    for (final layer in pausableLayers) {
      try {
        await layer.pause();
      } catch (e) {
        print('Error pausing layer ${layer.layerId}: $e');
      }
    }
  }

  /// Resume all paused layers
  Future<void> resumeAll() async {
    final pausedLayers = paused;
    for (final layer in pausedLayers) {
      try {
        await layer.resume();
      } catch (e) {
        print('Error resuming layer ${layer.layerId}: $e');
      }
    }
  }

  /// Send data to multiple layers
  Future<void> sendDataToLayers(
    List<String> layerIds,
    List<dynamic> data,
  ) async {
    for (final layerId in layerIds) {
      final layer = _layers[layerId];
      if (layer != null && layer.config.requiresOutlet) {
        try {
          await layer.sendData(data);
        } catch (e) {
          print('Error sending data to layer $layerId: $e');
        }
      }
    }
  }

  /// Get combined data stream from multiple layers
  Stream<LayerDataEvent> getCombinedDataStream(List<String> layerIds) {
    final streams =
        layerIds
            .map((id) => _layers[id]?.dataStream)
            .where((stream) => stream != null)
            .cast<Stream<LayerDataEvent>>();

    if (streams.isEmpty) {
      return const Stream.empty();
    }

    return StreamGroup.merge(streams);
  }

  /// Update known nodes for all layers
  void updateKnownNodes(List<NetworkNode> nodes) {
    for (final layer in _layers.values) {
      layer.updateKnownNodes(nodes);
    }
  }

  /// Dispose all layers
  Future<void> dispose() async {
    for (final layer in _layers.values) {
      try {
        await layer.dispose();
      } catch (e) {
        print('Error disposing layer ${layer.layerId}: $e');
      }
    }
    _layers.clear();
  }
}

/// Stream group utility for merging streams
class StreamGroup<T> {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    final controller = StreamController<T>.broadcast();
    final subscriptions = <StreamSubscription<T>>[];

    for (final stream in streams) {
      final subscription = stream.listen(
        controller.add,
        onError: controller.addError,
      );
      subscriptions.add(subscription);
    }

    controller.onCancel = () {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    };

    return controller.stream;
  }
}
