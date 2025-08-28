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
  liblsl_coordinator: [latest_version]
```

## Usage

### Basic Multi-layer Coordination

For more information, see the [liblsl.dart](https://github.com/NexusDynamic/liblsl.dart) repository.
