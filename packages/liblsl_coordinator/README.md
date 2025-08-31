# liblsl_coordinator

A performance-focused Dart library for multi-layer LSL-based device coordination. This library provides a robust foundation for coordinating multiple devices in real-time applications using Lab Streaming Layer (LSL) with support for different communication layers.

## Important note

If you see an error message like: 
```text
2025-08-31 16:16:06.339 (  30.482s) [R_TestData      ]      data_receiver.cpp:344    ERR| Stream transmission broke off (kqueue: Too many open files); re-connecting...
2025-08-31 16:16:06.339 (  30.482s) [R_TestData      ]      resolver_impl.cpp:209    ERR| Could not start a multicast resolve attempt for any of the allowed protocol stacks: open: Too many open files
````

This can happen (only on OSX?) due to the file descriptor limit being low by default. You can check your limit with:

```bash
ulimit -n
```

To increase it, you can run (e.g. to increase to 4096):

```bash
ulimit -n 4096
```

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
