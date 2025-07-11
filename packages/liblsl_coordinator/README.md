# liblsl_coordinator

A performance-focused Dart library for multi-layer LSL-based device coordination. This library provides a robust foundation for coordinating multiple devices in real-time applications using Lab Streaming Layer (LSL) with support for different communication layers.

## Features

- **Multi-layer Architecture**: Support for coordination, gaming, high-frequency, and custom stream layers
- **Automatic Coordinator Discovery**: Devices automatically find existing coordinators or promote themselves
- **Protocol Configuration**: Predefined and custom protocol configurations for different use cases
- **Pausable/Resumable Streams**: Game and sensor streams can be paused and resumed as needed
- **Isolate-based Processing**: Each layer runs in its own isolate for optimal performance
- **Flexible Stream Management**: Support for irregular frequency coordination and regular high-frequency data streams
- **Self-promotion Logic**: Automatic coordinator election when no coordinator is present

## Architecture

The library implements a layered approach where:

1. **Coordination Layer**: Always present, handles device discovery, role assignment, and protocol setup
2. **Data Layers**: Optional layers for specific data types (game, sensors, etc.)
3. **Stream Management**: Each layer has its own outlets and inlets managed in isolates
4. **Protocol System**: Configurable protocols define which layers are active and their properties

## Getting Started

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  liblsl_coordinator: ^0.0.1+2
  liblsl: ^0.8.0
```

## Usage

### Basic Multi-layer Coordination

```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

// Create a coordinator with gaming protocol
final coordinator = MultiLayerCoordinator(
  nodeId: 'device_001',
  nodeName: 'Gaming Device',
  protocolConfig: ProtocolConfigs.gaming, // coordination + game layers
);

// Listen to coordination events
coordinator.eventStream.listen((event) {
  switch (event.runtimeType) {
    case RoleChangedEvent _:
      final roleEvent = event as RoleChangedEvent;
      print('Role: ${roleEvent.newRole}');
      break;
      
    case NodeJoinedEvent _:
      final joinEvent = event as NodeJoinedEvent;
      print('Node joined: ${joinEvent.nodeName}');
      break;
      
    case ApplicationEvent _:
      final appEvent = event as ApplicationEvent;
      if (appEvent.type == 'protocol_ready') {
        print('Protocol ready - can start sending data');
      }
      break;
  }
});

// Initialize and join
await coordinator.initialize();
await coordinator.join();

// Access layers using the unified interface
final gameLayer = coordinator.getLayer('game');
if (gameLayer != null) {
  // Listen to game layer data
  gameLayer.dataStream.listen((dataEvent) {
    print('Game data from ${dataEvent.sourceNodeId}: ${dataEvent.data}');
  });
  
  // Send game data
  await gameLayer.sendData([x, y, vx, vy]);
  
  // Pause/resume game layer
  await gameLayer.pause();
  await gameLayer.resume();
}
```

### Protocol Configurations

The library provides several predefined protocols:

#### Basic Protocol
```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'device_001',
  nodeName: 'Basic Device',
  protocolConfig: ProtocolConfigs.basic, // coordination layer only
);
```

#### Gaming Protocol
```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'device_001',
  nodeName: 'Gaming Device',
  protocolConfig: ProtocolConfigs.gaming, // coordination + game layers
);
```

#### High-Frequency Protocol
```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'device_001',
  nodeName: 'EEG Device',
  protocolConfig: ProtocolConfigs.highFrequency, // coordination + hi-freq layers
);
```

#### Custom Protocol
```dart
final customProtocol = ProtocolConfig(
  protocolId: 'custom_experiment',
  protocolName: 'Custom Experiment',
  layers: [
    // Coordination layer (always required)
    StreamLayerConfig(
      layerId: 'coordination',
      layerName: 'Coordination',
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
    
    // Custom sensor layer
    StreamLayerConfig(
      layerId: 'sensors',
      layerName: 'Sensor Data',
      streamConfig: StreamConfig(
        streamName: 'sensor_data',
        streamType: LSLContentType.custom('sensors'),
        channelCount: 6, // 3-axis accel + 3-axis gyro
        sampleRate: 500.0,
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
```

### Unified Layer Interface

Each layer provides a consistent interface for operations:

```dart
// Get specific layer
final gameLayer = coordinator.getLayer('game');
if (gameLayer != null) {
  // Layer properties
  print('Layer: ${gameLayer.layerName}');
  print('Active: ${gameLayer.isActive}');
  print('Paused: ${gameLayer.isPaused}');
  print('Pausable: ${gameLayer.config.isPausable}');
  
  // Send data
  await gameLayer.sendData([x, y, vx, vy]);
  
  // Pause/resume operations
  await gameLayer.pause();
  await gameLayer.resume();
  
  // Listen to data
  gameLayer.dataStream.listen((dataEvent) {
    print('Data: ${dataEvent.data}');
  });
}

// Access all layers
final layers = coordinator.layers;

// Get layers by criteria
final pausableLayers = layers.pausable;
final highPriorityLayers = layers.getByPriority(LayerPriority.high);
final activeLayers = layers.active;

// Bulk operations
await layers.pauseAll();  // Pause all pausable layers
await layers.resumeAll(); // Resume all paused layers

// Send data to multiple layers
await layers.sendDataToLayers(['game', 'sensors'], data);

// Combined data streams
final combinedStream = layers.getCombinedDataStream(['game', 'sensors']);
combinedStream.listen((dataEvent) {
  print('${dataEvent.layerId}: ${dataEvent.data}');
});
```

## How It Works

### 1. Device Discovery and Promotion
- Devices start in `discovering` state
- Look for existing coordination streams
- If none found, promote self to coordinator
- If found, join as participant

### 2. Protocol Setup
- Coordinator sends protocol configuration to all participants
- Each device creates appropriate stream layers
- Coordinator has n_nodes inlets for coordination (one per participant)
- Participants have 1 inlet for coordinator messages

### 3. Stream Layer Creation
- **Coordination Layer**: Always present, handles control messages
- **Data Layers**: Created based on protocol configuration
- **Outlets**: Each device creates one outlet per layer (if required)
- **Inlets**: Each device creates inlets for other devices (if required)

### 4. Isolate-based Processing
- Each layer runs in its own isolate for performance
- Outlets run in separate isolates
- Inlet groups run in separate isolates
- Minimizes resource contention

### 5. Pausable Operations
- Game and sensor layers can be paused/resumed
- Paused inlets stop busy-wait polling
- Resumed inlets restart polling
- Coordination layer is never pausable

## Migration from liblsl_timing

If you're migrating from the original `liblsl_timing` implementation:

### Old way:
```dart
final coordinator = DeviceCoordinator(config, timingManager);
await coordinator.initialize();
await coordinator.signalReady();
```

### New way:
```dart
final coordinator = MultiLayerCoordinator(
  nodeId: config.deviceId,
  nodeName: config.deviceName,
  protocolConfig: ProtocolConfigs.gaming,
);
await coordinator.initialize();
await coordinator.join();
```

### Key differences:
- **Multi-layer support**: Can handle multiple stream types simultaneously
- **Protocol-based**: Configuration is declarative rather than imperative
- **Better isolation**: Each layer runs in its own isolate
- **More flexible**: Easy to add new layer types and configurations
- **Self-contained**: No external dependency on timing manager
- **Unified Layer Interface**: Clean, object-oriented API for layer operations

### API Comparison:

**Old approach:**
```dart
// Scattered methods on coordinator
await coordinator.pauseLayer('game');
await coordinator.sendLayerData('game', data);
coordinator.getLayerDataStream('game')?.listen(...);
```

**New unified approach:**
```dart
// Clean layer interface
final gameLayer = coordinator.getLayer('game');
await gameLayer.pause();
await gameLayer.sendData(data);
gameLayer.dataStream.listen(...);

// Bulk operations on layer collection
final layers = coordinator.layers;
await layers.pauseAll();
await layers.sendDataToLayers(['game', 'sensors'], data);
```

## Performance Considerations

- **Isolate Usage**: Each layer runs in its own isolate for optimal performance
- **Pausable Streams**: Use pause/resume to reduce resource usage when not needed
- **Layer Priorities**: Configure layer priorities for resource allocation
- **Buffer Management**: Customize buffer sizes per layer based on requirements

## Examples

See the `example/` directory for complete examples:

- `unified_layer_example.dart`: Demonstrates the new unified layer interface
- `multi_layer_example.dart`: Basic multi-layer coordination
- `liblsl_coordinator_example.dart`: Original API example

## Additional Information

This library is designed to be the foundation for real-time multi-device coordination applications. It provides:

- **Scalability**: Support for many devices with minimal overhead
- **Reliability**: Automatic coordinator election and recovery
- **Performance**: Isolate-based processing for optimal throughput
- **Flexibility**: Custom protocols and layer configurations
- **Maintainability**: Clean separation of concerns

For more information, see the [liblsl.dart](https://github.com/NexusDynamic/liblsl.dart) repository.