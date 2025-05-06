import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:liblsl_timing/src/timing_manager.dart';

/// Handler for external timing hardware integration
class ExternalHardwareManager {
  final TimingManager timingManager;
  bool _isInitialized = false;

  // For Bluetooth connections
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;

  // Connected device
  DiscoveredDevice? _connectedDevice;
  QualifiedCharacteristic? _dataCharacteristic;

  // Configuration
  bool _usePhotodiode = false;
  bool _useFsrSensor = false;
  String _deviceName = 'TimingDevice';

  ExternalHardwareManager(this.timingManager);

  bool get isInitialized => _isInitialized;
  bool get isConnected => _connectedDevice != null;

  /// Initialize the hardware manager
  Future<void> initialize({
    bool usePhotodiode = false,
    bool useFsrSensor = false,
    String deviceName = 'TimingDevice',
  }) async {
    _usePhotodiode = usePhotodiode;
    _useFsrSensor = useFsrSensor;
    _deviceName = deviceName;

    if (_usePhotodiode || _useFsrSensor) {
      // Start scanning for devices
      await _startScan();
    }

    _isInitialized = true;
  }

  /// Start scanning for BLE devices
  Future<void> _startScan() async {
    _scanSubscription?.cancel();

    _scanSubscription = _ble
        .scanForDevices(
          withServices: [], // Empty list means all devices
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            // Look for our device by name
            if (device.name == _deviceName) {
              _connectToDevice(device);
            }
          },
          onError: (error) {
            print('BLE scan error: $error');
          },
        );

    // Stop scanning after 10 seconds
    Timer(const Duration(seconds: 10), () {
      _scanSubscription?.cancel();
    });
  }

  /// Connect to a specific BLE device
  Future<void> _connectToDevice(DiscoveredDevice device) async {
    // Cancel any previous connection
    await disconnect();

    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (connectionState) {
            if (connectionState.connectionState ==
                DeviceConnectionState.connected) {
              _connectedDevice = device;
              _discoverServices();
            } else if (connectionState.connectionState ==
                DeviceConnectionState.disconnected) {
              _connectedDevice = null;
              _dataCharacteristic = null;
            }
          },
          onError: (error) {
            print('BLE connection error: $error');
          },
        );
  }

  /// Discover services on the connected device
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    try {
      await _ble.discoverAllServices(_connectedDevice!.id);
      final services = await _ble.getDiscoveredServices(_connectedDevice!.id);
      // Find the service and characteristic for our timing data
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          // Check if this is our data characteristic
          // In a real implementation, you'd check for specific UUIDs
          if (characteristic.isNotifiable) {
            _dataCharacteristic = QualifiedCharacteristic(
              characteristicId: characteristic.id,
              serviceId: service.id,
              deviceId: _connectedDevice!.id,
            );

            // Subscribe to notifications
            _subscribeToCharacteristic();
            break;
          }
        }
        if (_dataCharacteristic != null) break;
      }
    } catch (e) {
      print('Error discovering services: $e');
    }
  }

  /// Subscribe to notifications from the device
  void _subscribeToCharacteristic() {
    if (_dataCharacteristic == null) return;

    _dataSubscription = _ble
        .subscribeToCharacteristic(_dataCharacteristic!)
        .listen(
          (data) {
            // Process the incoming data
            _processIncomingData(data);
          },
          onError: (error) {
            print('BLE data error: $error');
          },
        );
  }

  /// Process data from the external hardware
  void _processIncomingData(List<int> data) {
    if (data.isEmpty) return;

    // The format of the data will depend on your specific hardware
    // This is a simplified example

    // First byte indicates data type
    final dataType = data[0];

    switch (dataType) {
      case 1: // Photodiode event
        if (_usePhotodiode) {
          final timestamp = _extractTimestamp(data, 1);
          final value = data.length > 9 ? data[9] : 0;

          timingManager.recordTimestampedEvent(
            'photodiode_event',
            timestamp,
            description: 'Photodiode detected change',
            metadata: {'value': value},
          );
        }
        break;

      case 2: // FSR sensor event
        if (_useFsrSensor) {
          final timestamp = _extractTimestamp(data, 1);
          final pressure = _extractPressure(data, 9);

          timingManager.recordTimestampedEvent(
            'fsr_event',
            timestamp,
            description: 'FSR sensor detected pressure',
            metadata: {'pressure': pressure},
          );
        }
        break;
    }
  }

  /// Extract timestamp from byte array
  double _extractTimestamp(List<int> data, int offset) {
    // Assuming 8-byte double timestamp starting at offset
    if (data.length < offset + 8) return 0.0;

    // This is a simplified implementation
    // In a real app, you'd use ByteData to decode the timestamp properly
    final buffer = ByteData(8);
    for (int i = 0; i < 8; i++) {
      buffer.setUint8(i, data[offset + i]);
    }

    return buffer.getFloat64(0, Endian.little);
  }

  /// Extract pressure value from byte array
  double _extractPressure(List<int> data, int offset) {
    // Assuming 4-byte float pressure starting at offset
    if (data.length < offset + 4) return 0.0;

    final buffer = ByteData(4);
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(i, data[offset + i]);
    }

    return buffer.getFloat32(0, Endian.little);
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    _dataSubscription?.cancel();
    _dataSubscription = null;

    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _connectedDevice = null;
    _dataCharacteristic = null;
  }

  /// Clean up resources
  void dispose() {
    _scanSubscription?.cancel();
    disconnect();
  }
}
