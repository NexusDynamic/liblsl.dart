# Resource Management Guide

This guide explains proper resource management patterns for the `liblsl_coordinator` library. Following these patterns is critical to avoid resource leaks, LSL stream conflicts, and application crashes.

## Core Principles

### 1. Always Use Try-Finally Blocks

```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'unique_id',
  nodeName: 'My Device',
  protocolConfig: ProtocolConfigs.basic,
);

try {
  await coordinator.initialize();
  // Use coordinator...
} finally {
  // CRITICAL: Always dispose
  await coordinator.dispose();
  
  // Allow time for LSL resources to be released
  await Future.delayed(const Duration(milliseconds: 100));
}
```

### 2. Use Unique Node IDs

Each coordinator instance requires a globally unique node ID:

```dart
// Good: Unique IDs
final coordinator1 = MultiLayerCoordinator(
  nodeId: 'device_${DateTime.now().millisecondsSinceEpoch}',
  // ...
);

// Bad: Duplicate IDs will cause conflicts
final coordinator2 = MultiLayerCoordinator(
  nodeId: 'device_1', // Same ID as another coordinator
  // ...
);
```

### 3. Sequential vs Concurrent Usage

**Recommended: Sequential Usage**
```dart
// Good: Use coordinators one at a time
for (final config in configurations) {
  final coordinator = MultiLayerCoordinator(/* ... */);
  try {
    await coordinator.initialize();
    // Use coordinator...
  } finally {
    await coordinator.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
```

**Current Limitation: Concurrent Usage**
```dart
// Limited: Multiple coordinators simultaneously may cause LSL conflicts
// This is a known limitation of the current implementation
final coord1 = MultiLayerCoordinator(/* ... */);
final coord2 = MultiLayerCoordinator(/* ... */);
// Initializing both simultaneously may cause issues
```

## Coordinator Lifecycle Patterns

### Basic Coordinator

```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'basic_${DateTime.now().millisecondsSinceEpoch}',
  nodeName: 'Basic Device',
  protocolConfig: ProtocolConfigs.basic,
);

try {
  await coordinator.initialize();
  expect(coordinator.isActive, isTrue);
  
  // Basic coordinator has placeholder layers
  expect(coordinator.layers.length, equals(1));
  expect(coordinator.role, equals(NodeRole.discovering));
  
} finally {
  await coordinator.dispose();
  await Future.delayed(const Duration(milliseconds: 100));
}
```

### Promoted Coordinator

```dart
final coordinator = MultiLayerCoordinator(
  nodeId: 'promoted_${DateTime.now().millisecondsSinceEpoch}',
  nodeName: 'Promoted Device',
  protocolConfig: ProtocolConfigs.gaming,
  coordinationConfig: CoordinationConfig(
    discoveryInterval: 0.1,
    heartbeatInterval: 0.1,
    joinTimeout: 1.0,
    autoPromote: true,
  ),
);

try {
  await coordinator.initialize();
  await coordinator.join();
  
  // Wait for coordinator promotion - this timing is critical
  await Future.delayed(const Duration(milliseconds: 1200));
  
  expect(coordinator.role, equals(NodeRole.coordinator));
  
  // Now layers are active and can be used for real operations
  final gameLayer = coordinator.getLayer('game');
  expect(gameLayer!.isActive, isTrue);
  await gameLayer.sendData([1.0, 2.0, 3.0]);
  
} finally {
  await coordinator.dispose();
  // Promoted coordinators need extra cleanup time
  await Future.delayed(const Duration(milliseconds: 300));
}
```

## Error Handling Patterns

### Initialization Failures

```dart
final coordinator = MultiLayerCoordinator(/* invalid config */);

try {
  await coordinator.initialize(); // May throw
} catch (e) {
  print('Initialization failed: $e');
  // Handle error appropriately
} finally {
  // CRITICAL: Always dispose, even after failures
  try {
    await coordinator.dispose();
  } catch (e) {
    print('Cleanup error: $e'); // Log but don't rethrow
  }
}
```

### Stream Subscription Management

```dart
final coordinator = MultiLayerCoordinator(/* ... */);
StreamSubscription? subscription;

try {
  await coordinator.initialize();
  
  subscription = coordinator.eventStream.listen((event) {
    // Handle events
  });
  
  // Use coordinator...
  
} finally {
  // CRITICAL: Cancel subscriptions before disposing coordinator
  await subscription?.cancel();
  await coordinator.dispose();
}
```

## Common Mistakes to Avoid

### ❌ Forgetting to Dispose
```dart
// BAD: Resource leak
final coordinator = MultiLayerCoordinator(/* ... */);
await coordinator.initialize();
// Missing dispose() - resources leak!
```

### ❌ Not Waiting for Promotion
```dart
// BAD: Timing issues
await coordinator.join();
// Missing delay - coordinator might not be promoted yet
expect(coordinator.role, equals(NodeRole.coordinator)); // May fail
```

### ❌ Reusing Disposed Coordinators
```dart
// BAD: Using disposed coordinator
await coordinator.dispose();
await coordinator.initialize(); // Error: Coordinator cannot be reused
```

### ❌ Insufficient Cleanup Delays
```dart
// BAD: Resource conflicts
await coordinator1.dispose();
// Missing delay
final coordinator2 = MultiLayerCoordinator(/* ... */);
await coordinator2.initialize(); // May conflict with coordinator1's resources
```

## Best Practices Summary

1. **Always use try-finally blocks** for coordinator disposal
2. **Use unique node IDs** for each coordinator instance
3. **Prefer sequential usage** over concurrent coordinators
4. **Wait for promotion** (1200ms) before using coordinator features
5. **Cancel subscriptions** before disposing coordinators
6. **Add cleanup delays** between coordinator operations
7. **Handle errors gracefully** without skipping cleanup
8. **Don't reuse disposed coordinators** - create new instances instead

## Performance Considerations

- Coordinator promotion takes ~1200ms (1000ms joinTimeout + 200ms LSL delays)
- LSL resource cleanup takes 100-300ms depending on coordinator complexity
- Sequential coordinator usage is safer than concurrent usage
- Use appropriate protocol configs (basic vs gaming vs highFrequency) based on needs

## Testing Patterns

When writing tests, create fresh coordinator instances for each test:

```dart
group('My Tests', () {
  test('should do something', () async {
    final coordinator = createTestCoordinator();
    try {
      await coordinator.initialize();
      // Test logic...
    } finally {
      await safeDisposeCoordinator(coordinator);
    }
  });
});
```

This ensures test isolation and prevents resource conflicts between tests.