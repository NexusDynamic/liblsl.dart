import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../transport.dart';

SerialPortProvider createPlatformSerialPortProvider() =>
    const WebSerialPortProvider();

// Minimal WebSerial bindings (https://wicg.github.io/serial/), which
// package:web does not include.

extension type _Serial._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_SerialPort>> getPorts();
  external JSPromise<_SerialPort> requestPort([_SerialPortRequestOptions opts]);
}

extension type _SerialPortRequestOptions._(JSObject _) implements JSObject {
  external factory _SerialPortRequestOptions({
    JSArray<_SerialPortFilter> filters,
  });
}

extension type _SerialPortFilter._(JSObject _) implements JSObject {
  external factory _SerialPortFilter();
  external set usbVendorId(int value);
  external set usbProductId(int value);
}

extension type _SerialPort._(JSObject _) implements JSObject {
  external web.ReadableStream? get readable;
  external web.WritableStream? get writable;
  external JSPromise<JSAny?> open(_SerialOptions options);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> setSignals(_SerialOutputSignals signals);
  external _SerialPortInfo getInfo();
}

extension type _SerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

extension type _SerialOptions._(JSObject _) implements JSObject {
  external factory _SerialOptions({int baudRate, int bufferSize});
}

extension type _SerialOutputSignals._(JSObject _) implements JSObject {
  external factory _SerialOutputSignals({bool dataTerminalReady});
}

_Serial? get _serial {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has('serial')) return null;
  return navigator['serial'] as _Serial?;
}

/// Serial ports through WebSerial (Chromium-based browsers, over HTTPS or
/// localhost).
///
/// Browsers only expose ports the user picked: call [requestPort] from a
/// user gesture first. Afterwards [listPorts] includes them, also after a
/// page reload.
class WebSerialPortProvider implements SerialPortProvider {
  const WebSerialPortProvider();

  @override
  bool get isSupported => _serial != null;

  @override
  bool get requiresUserSelection => true;

  @override
  Future<List<SerialPortInfo>> listPorts() async {
    final serial = _checkSupported();
    final ports = (await serial.getPorts().toDart).toDart;
    return [for (var i = 0; i < ports.length; i++) _info(ports[i], i)];
  }

  @override
  Future<SerialPortInfo?> requestPort({
    List<SerialPortFilter> filters = const [],
    bool Function(SerialPortInfo port)? where,
  }) async {
    final serial = _checkSupported();
    final jsFilters = <_SerialPortFilter>[
      for (final f in filters)
        _SerialPortFilter()
          ..setIfNotNull('usbVendorId', f.usbVendorId)
          ..setIfNotNull('usbProductId', f.usbProductId),
    ];
    try {
      final port = await serial
          .requestPort(_SerialPortRequestOptions(filters: jsFilters.toJS))
          .toDart;
      final granted = (await serial.getPorts().toDart).toDart;
      final index = granted.indexWhere((p) => p.strictEquals(port).toDart);
      return _info(port, index);
    } catch (e) {
      // A DOMException named NotFoundError means the user cancelled.
      if ('$e'.contains('NotFoundError')) return null;
      throw SerialException('$e');
    }
  }

  @override
  Future<SerialTransport> open(SerialPortInfo port) async {
    _checkSupported();
    final handle = port.handle;
    if (handle is! _PortHandle) {
      throw ArgumentError.value(port, 'port', 'not a WebSerial port');
    }
    return WebSerialTransport._open(handle.port);
  }

  _Serial _checkSupported() {
    final serial = _serial;
    if (serial == null) {
      throw UnsupportedError(
        'WebSerial is not available in this browser (it needs a '
        'Chromium-based browser and a secure context).',
      );
    }
    return serial;
  }

  static SerialPortInfo _info(_SerialPort port, int index) {
    final info = port.getInfo();
    final vid = info.usbVendorId;
    final pid = info.usbProductId;
    return SerialPortInfo(
      id: '$index',
      description: vid == null
          ? 'Serial port'
          : 'USB serial port ${vid.toRadixString(16).padLeft(4, '0')}:'
                '${(pid ?? 0).toRadixString(16).padLeft(4, '0')}',
      vendorId: vid,
      productId: pid,
      handle: _PortHandle(port),
    );
  }
}

/// Wraps the JS port object, so [SerialPortInfo.handle] can be type checked.
class _PortHandle {
  final _SerialPort port;
  const _PortHandle(this.port);
}

extension on JSObject {
  void setIfNotNull(String key, int? value) {
    if (value != null) this[key] = value.toJS;
  }
}

/// An open WebSerial port.
class WebSerialTransport implements SerialTransport {
  final _SerialPort _port;
  final web.ReadableStreamDefaultReader _reader;
  final web.WritableStreamDefaultWriter _writer;
  final StreamController<Uint8List> _input = StreamController<Uint8List>();
  Future<void>? _closing;

  WebSerialTransport._(this._port, this._reader, this._writer) {
    _readLoop();
  }

  static Future<WebSerialTransport> _open(_SerialPort port) async {
    try {
      // USB CDC ignores the baud rate; the value matches the native library.
      await port
          .open(_SerialOptions(baudRate: 230400, bufferSize: 65536))
          .toDart;
    } catch (e) {
      throw SerialException('Failed to open serial port: $e');
    }
    try {
      await port
          .setSignals(_SerialOutputSignals(dataTerminalReady: false))
          .toDart;
    } catch (_) {
      // Not all devices support control signals.
    }
    final reader =
        port.readable!.getReader() as web.ReadableStreamDefaultReader;
    final writer = port.writable!.getWriter();
    return WebSerialTransport._(port, reader, writer);
  }

  Future<void> _readLoop() async {
    try {
      while (true) {
        final result = await _reader.read().toDart;
        if (result.done) break;
        final value = result.value;
        if (value != null && !_input.isClosed) {
          _input.add((value as JSUint8Array).toDart);
        }
      }
    } catch (e) {
      if (_closing == null && !_input.isClosed) {
        _input.addError(SerialException('Serial read failed: $e'));
      }
    }
    if (_closing == null) unawaited(close());
  }

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> write(List<int> data) async {
    if (_closing != null) throw const SerialException('Serial port is closed');
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    await _writer.write(bytes.toJS).toDart;
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _reader.cancel().toDart;
    } catch (_) {}
    _reader.releaseLock();
    try {
      await _writer.close().toDart;
    } catch (_) {}
    _writer.releaseLock();
    try {
      await _port.close().toDart;
    } catch (_) {}
    if (!_input.isClosed) await _input.close();
  }
}
