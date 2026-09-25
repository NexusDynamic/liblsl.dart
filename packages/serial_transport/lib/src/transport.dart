import 'dart:async';
import 'dart:typed_data';

import 'platform_stub.dart'
    if (dart.library.ffi) 'native/native_serial.dart'
    if (dart.library.js_interop) 'web/web_serial.dart';

/// A byte connection to a device, e.g. a serial port.
///
/// Implement this to connect through anything the library does not cover,
/// such as a USB serial plugin on Android.
abstract interface class SerialTransport {
  /// Bytes received from the device. Single subscription; closes when the
  /// transport is closed or the device disconnects (with an error for the
  /// latter where the platform reports one).
  Stream<Uint8List> get input;

  /// Send [data] to the device.
  Future<void> write(List<int> data);

  /// Close the connection. Safe to call more than once.
  Future<void> close();
}

/// A serial port found by a [SerialPortProvider].
class SerialPortInfo {
  /// Platform identifier: a device path or COM port name on desktop, an
  /// index on the web.
  final String id;

  /// Human readable name, e.g. the USB product string.
  final String description;

  /// USB vendor and product ids, if known.
  final int? vendorId;
  final int? productId;

  /// The USB product string (the bus reported device description on
  /// Windows), or null if unknown (e.g. on the web). Devices can often be
  /// recognised by it.
  final String? product;

  /// Platform object behind the port (e.g. a WebSerial `SerialPort`).
  final Object? handle;

  const SerialPortInfo({
    required this.id,
    this.description = '',
    this.vendorId,
    this.productId,
    this.product,
    this.handle,
  });

  @override
  String toString() {
    final ids = vendorId == null
        ? ''
        : ' [${_hex4(vendorId!)}:${_hex4(productId ?? 0)}]';
    final p = product == null || product == description ? '' : ' ($product)';
    return '$id: $description$ids$p';
  }

  static String _hex4(int v) => v.toRadixString(16).padLeft(4, '0');
}

/// USB ids to filter the port chooser by (WebSerial `requestPort`).
class SerialPortFilter {
  final int? usbVendorId;
  final int? usbProductId;

  const SerialPortFilter({this.usbVendorId, this.usbProductId});
}

/// Finds and opens serial ports on the current platform.
///
/// Use [SerialPortProvider.platform] for the built-in implementation:
/// native serial ports on Linux, macOS and Windows, WebSerial in browsers
/// that support it. Other platforms (Android, iOS) need an app-provided
/// [SerialTransport].
abstract interface class SerialPortProvider {
  /// The built-in provider for the current platform.
  factory SerialPortProvider.platform() => createPlatformSerialPortProvider();

  /// Whether serial ports are available here.
  bool get isSupported;

  /// Whether the user has to pick a port with [requestPort] before it shows
  /// up in [listPorts] (the web).
  bool get requiresUserSelection;

  /// Ports that can be opened. On the web, only ports the user has already
  /// granted access to.
  Future<List<SerialPortInfo>> listPorts();

  /// Ask the user to choose a port (web only; must be called from a user
  /// gesture such as a click). Returns null if the user cancelled. On other
  /// platforms, returns the first port that matches [filters] and [where]
  /// (e.g. a device recognised by its [SerialPortInfo.product]), if any.
  Future<SerialPortInfo?> requestPort({
    List<SerialPortFilter> filters = const [],
    bool Function(SerialPortInfo port)? where,
  });

  /// Open [port], at [baudRate] bits per second if given (USB CDC devices
  /// ignore it; UART adapters need it).
  Future<SerialTransport> open(SerialPortInfo port, {int? baudRate});
}

/// Thrown when a serial port cannot be opened, read or written.
class SerialException implements Exception {
  final String message;

  const SerialException(this.message);

  @override
  String toString() => 'SerialException: $message';
}
