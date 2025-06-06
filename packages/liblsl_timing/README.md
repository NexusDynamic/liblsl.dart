# LSL Timing Test Package

A Flutter application for comprehensive timing analysis and performance testing of Lab Streaming Layer (LSL) implementations using the [liblsl](https://pub.dev/packages/liblsl) Dart package. This tool is designed for researchers and developers who need to measure and validate high-precision timing characteristics in LSL-based systems.

## Overview

The LSL Timing Test Package provides a suite of coordinated multi-device tests to analyze various timing aspects of LSL streaming:

- **Network latency measurement** between LSL producers and consumers
- **Clock synchronization analysis** across multiple devices
- **End-to-end timing validation** with interactive button/sensor tests
- **Real-time coordination** between multiple test devices
- **Comprehensive data export** for post-processing and analysis

## Features

### 🎯 Test Types

1. **Latency Test**
   - Measures communication time between LSL sample transmission and reception
   - Supports configurable sample rates and data formats
   - Records precise timestamps using both Dart and LSL clocks
   - Isolate-based processing for minimal timing interference

2. **Clock Synchronization Test**
   - Analyzes time differences and drift between devices
   - Periodic time correction measurements
   - Statistical analysis of synchronization accuracy
   - Multi-device coordination for comprehensive drift analysis

3. **Interactive Button Test**
   - End-to-end timing validation with user interaction
   - Button press triggers LSL marker transmission
   - Visual feedback (black square) on marker reception
   - Perfect for external sensor validation (FSR, photodiodes, etc.)

### 🌐 Multi-Device Coordination

- **Automatic device discovery** using LSL control streams
- **Coordinator/participant roles** with automatic fallback
- **Synchronized test execution** across all connected devices
- **Real-time status messaging** and coordination
- **Ready state management** ensuring all devices start simultaneously

### 📊 Data Collection & Export

- **High-precision timestamping** with microsecond resolution
- **Comprehensive event logging** for all timing-critical operations
- **TSV export format** for easy analysis in research tools
- **Metadata tracking** including device IDs, test configurations, and timing corrections
- **Real-time event streaming** for live monitoring

### ⚙️ Configuration Management

- **Persistent device settings** using SharedPreferences
- **Flexible stream configuration** (sample rates, channel counts, data types)
- **Role-based testing** (producer, consumer, or both)
- **Network timeout and buffer management**
- **Multi-language support** (English, Danish, more support easily added)

## Installation

1. **Prerequisites**
   ```bash
   flutter --version
   ```

    - Ensure you have the Flutter SDK installed and configured see: [Flutter Installation Guide](https://docs.flutter.dev/get-started/install).

2. **Clone and build**
   ```bash
   git clone git@github.com:zeyus/liblsl.dart.git liblsl.dart
   cd liblsl.dart/packages/liblsl_timing
   flutter pub get
   flutter run --release # or flutter run --debug for development mode, with verbose logging NOTE: Debug mode will introduce timing inaccuracies, for accurate timing measurements use release mode.
   ```

3. **Platform-specific setup**
   - **Android**: Requires location and notification permissions for network discovery
   - **iOS**: Requires network permissions in Info.plist, in addition, liblsl requires the Multicast entitlement (requires an Apple Developer account with this entitlement granted).
   - **Desktop**: No additional setup required

## Usage

### Quick Start

1. **Launch the app** on multiple devices connected to the same network
2. **Configure device settings** (name, role, stream parameters)
3. **Wait for device discovery** - one device automatically becomes coordinator
4. **Select and start tests** from the coordinator device
5. **Monitor real-time results** and export data when complete

### Device Roles

- **Coordinator**: Controls test execution, manages device discovery
- **Participant**: Follows coordinator commands, contributes to tests
- **Producer**: Sends LSL data streams during tests
- **Consumer**: Receives LSL data streams during tests

*Note: Devices can be both producers and consumers simultaneously.*

### Data Export

Exported TSV files contain:
- `log_timestamp`: System time when event was logged
- `timestamp`: Dart/Flutter timestamp 
- `event_id`: Unique identifier for the event
- `event_type`: Type of timing event (sampleSent, sampleReceived, etc.)
- `lsl_clock`: LSL library timestamp
- `description`: Human-readable event description
- `metadata`: JSON object with additional event data

## Architecture

### Core Components

- **TimingManager**: Centralized event collection and timestamp management
- **DeviceCoordinator**: Multi-device discovery and test coordination
- **TestController**: Test lifecycle management and execution
- **IsolateManager**: High-precision sample processing in separate isolates
- **DataExporter**: Structured data export and file management

### Timing Precision

- **Isolate-based processing** minimizes main thread interference
- **Dual timestamp recording** (Dart + LSL) for cross-validation
- **Microsecond resolution** throughout the timing pipeline
- **Busy-wait loops** for critical timing sections
- **Time base calibration** between different clock sources

### Network Architecture

- **LSL-based device discovery** using irregular marker streams
- **JSON message protocol** for coordination commands
- **Automatic coordinator election** with fallback mechanisms
- **Resilient inlet/outlet management** with recovery capabilities

## Research Applications

### Typical Use Cases

1. **Neuroscience Research**
   - EEG/MEG timing validation
   - Stimulus-response latency measurement
   - Multi-modal synchronization testing

2. **Real-time Systems**
   - Industrial control system validation
   - Robotics communication testing
   - Sensor network timing analysis

3. **Performance Benchmarking**
   - LSL implementation comparison
   - Network infrastructure validation
   - Cross-platform timing analysis

### Integration with External Hardware

The interactive test mode is specifically designed for integration with external measurement devices:

```
[Physical Button/FSR] → [External Device] → [LSL Stream] → [App Display]
                                     ↓
[Physical Photodiode] ← [Screen Display] ← [Visual Feedback]
```

This enables complete end-to-end timing validation from physical input to visual output.

## Configuration Options

### Stream Settings
- **Sample Rate**: 1Hz - 1kHz+ (hardware dependent)
- **Channel Count**: 1-64 channels per stream
- **Data Format**: float32, int32, string markers
- **Buffer Sizes**: Configurable for low-latency vs. reliability

### Test Parameters
- **Duration**: 10 seconds - 3 minutes
- **Coordination Timeout**: 1-60 seconds
- **Maximum Streams**: 1-100 concurrent streams
- **Recovery Mode**: Automatic reconnection on stream loss

### Device Settings
- **Unique Device ID**: Auto-generated or manual
- **Network Interface**: Automatic detection with manual IP display
- **Language**: English/Danish with extensible localization
- **Permissions**: Automatic request for required platform permissions

## Performance Considerations

### Optimization Features

- **Wakelock management** prevents device sleep during tests
- **Fullscreen mode** reduces system interference on mobile
- **Buffered event processing** reduces I/O overhead during tests
- **Efficient memory management** for long-duration tests


## Troubleshooting

### Common Issues

1. **Device Discovery Fails**
   - Verify all devices on same network
   - Check firewall settings for LSL ports
   - Ensure location permissions granted (Android)

2. **High Timing Variance**
   - Use wired connections when possible
   - Close background applications
   - Enable performance mode on mobile devices

3. **Test Coordination Problems**
   - Restart coordinator device
   - Check network stability
   - Verify time synchronization between devices

### Debug Output

By default, flutter runs in debug mode, which provides detailed logging. You can adjust the log level for more or less verbosity:
```dart
if (kDebugMode) {
  // Detailed logging enabled
  logLevel = 0;  // Verbose LSL logging
}
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Maintain microsecond-precision timing throughout
- Add comprehensive event logging for new features
- Test on multiple platforms and network configurations
- Update documentation for any API changes
- Follow Dart/Flutter style guidelines

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

## Acknowledgments

- Built on the [liblsl.dart](https://github.com/zeyus/liblsl.dart) package
- [Christian A. Kothe: liblsl](https://github.com/sccn/liblsl) for the LSL library
- Dart/Flutter framework by Google
