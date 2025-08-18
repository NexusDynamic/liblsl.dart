# Conditional Import System Implementation

This document outlines the conditional import system that enables automatic transport selection based on the target platform.

## Overview

The liblsl_coordinator package now supports automatic transport selection:
- **LSL Transport**: Used on native platforms (Android, iOS, macOS, Windows, Linux)
- **WebSocket Transport**: Used on web platforms (and as fallback on other platforms)

## Architecture

### Core Components

1. **Transport-Agnostic Factory** (`src/coordinator_factory.dart`)
   - `CoordinatorFactory`: Main entry point with automatic transport selection
   - `SessionConfig`: Universal session configuration
   - `SessionResult`: Transport-agnostic session result

2. **Transport Adapters**
   - `LSLTransportFactory`: Adapts existing LSL implementation to standard interface
   - `WebSocketTransportFactory`: Provides WebSocket-based coordination

3. **Conditional Imports**
   ```dart
   import 'transport/lsl/create_network_session.dart'
       if (dart.library.js) 'transport/websocket/create_network_session.dart'
       as transport_impl;
   ```

4. **Platform-Specific Libraries**
   - `liblsl_coordinator.dart`: Core universal API
   - `liblsl_coordinator_lsl.dart`: LSL-enabled library for native platforms
   - `liblsl_coordinator_web.dart`: WebSocket-enabled library for web platforms

## Usage Patterns

### Universal Usage (Recommended)

```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

// Automatically uses LSL on native, WebSocket on web
final result = await CoordinatorFactory.createSession(
  sessionId: 'my_session',
  nodeId: 'node_1',
  nodeName: 'My Node',
  topology: NetworkTopology.hierarchical,
);

final session = result.session;
await session.join();
```

### Platform-Specific Usage

**For Native Platforms (with full LSL features):**
```dart
import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';

// Use both universal and LSL-specific APIs
final result = await CoordinatorFactory.createSession(/* ... */);

// Or use LSL-specific factory for advanced features
await LSLNetworkFactory.instance.initialize();
final networkSession = await LSLNetworkFactory.instance.createNetwork(/* ... */);
final dataStream = await networkSession.createDataStream(
  StreamConfigs.eegProducer(/* ... */),
);
```

**For Web Platforms:**
```dart
import 'package:liblsl_coordinator/liblsl_coordinator_web.dart';

// Universal API automatically uses WebSocket transport
final result = await CoordinatorFactory.createSession(/* ... */);
```

## File Organization

```
lib/
├── liblsl_coordinator.dart              # Universal API
├── liblsl_coordinator_lsl.dart          # LSL-enabled API
├── liblsl_coordinator_web.dart          # WebSocket-enabled API
└── src/
    ├── coordinator_factory.dart         # Main factory with conditional imports
    ├── session_config.dart              # Universal configuration
    ├── coordinator_factory_interface.dart # Transport interface
    └── transport/
        ├── lsl/
        │   ├── lsl_factory_adapter.dart # LSL transport adapter
        │   └── create_network_session.dart # LSL conditional import function
        └── websocket/
            ├── ws_factory_adapter.dart  # WebSocket transport adapter
            └── create_network_session.dart # WebSocket conditional import function
```

## Benefits

✅ **Compile-time Safety**: Web builds never include LSL dependencies  
✅ **Zero Runtime Overhead**: No reflection or dynamic loading  
✅ **Unified API**: Same code works on all platforms  
✅ **Transport Control**: Advanced users can choose specific transports  
✅ **Backwards Compatible**: Existing LSL-specific code continues to work  

## Migration Guide

### From LSL-Specific Code

**Before:**
```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

await LSLNetworkFactory.instance.initialize();
final session = await LSLNetworkFactory.instance.createNetwork(/* ... */);
```

**After (Universal):**
```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

final result = await CoordinatorFactory.createSession(/* ... */);
final session = result.session;
```

**After (LSL-Specific):**
```dart
import 'package:liblsl_coordinator/liblsl_coordinator_lsl.dart';

// Same code as before - no changes needed
await LSLNetworkFactory.instance.initialize();
final session = await LSLNetworkFactory.instance.createNetwork(/* ... */);
```

### For New Projects

Start with the universal API:

```dart
import 'package:liblsl_coordinator/liblsl_coordinator.dart';

void main() async {
  // Check which transport is being used
  final transportInfo = CoordinatorFactory.getTransportInfo();
  print('Using transport: ${transportInfo['name']}');

  // Create session - works everywhere
  final result = await CoordinatorFactory.createSession(
    sessionId: 'cross_platform_session',
    nodeId: 'universal_node',
    nodeName: 'Universal Node',
    topology: NetworkTopology.hierarchical,
  );

  await result.session.join();
  // ... use session
  await result.session.leave();
  await CoordinatorFactory.dispose();
}
```

## Implementation Status

- ✅ Transport-agnostic factory interface
- ✅ LSL transport adapter
- ✅ WebSocket transport stub (basic implementation)
- ✅ Conditional import system
- ✅ Platform-specific library entry points
- ✅ Universal usage examples
- ⏳ Complete WebSocket transport implementation (future work)
- ⏳ Advanced WebSocket features (WebRTC, TURN servers, etc.)

## Future Enhancements

1. **Complete WebSocket Implementation**: Full peer-to-peer coordination using WebRTC
2. **Additional Transports**: gRPC, raw TCP, custom protocols
3. **Transport Selection Logic**: More sophisticated platform detection
4. **Configuration Validation**: Transport-specific config validation
5. **Performance Optimizations**: Transport-specific optimizations