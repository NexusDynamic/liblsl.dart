import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../transport.dart';
import 'serial_bindings.g.dart' as hss;

SerialPortProvider createPlatformSerialPortProvider() =>
    const NativeSerialPortProvider();

const int _errLen = 512;
const int _readBufferSize = 4096;

/// Read timeout of the I/O isolate: writes and close requests wait at most
/// this long.
const int _readTimeoutMs = 20;

/// Serial ports through the native shim (src/hs_serial.c), on Linux, macOS
/// and Windows.
class NativeSerialPortProvider implements SerialPortProvider {
  const NativeSerialPortProvider();

  @override
  bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  bool get requiresUserSelection => false;

  @override
  Future<List<SerialPortInfo>> listPorts() async {
    _checkSupported();
    // Enumeration can take a while on Windows, so keep it off this isolate.
    final text = await Isolate.run(_listPortsSync);
    return [
      for (final line in text.split('\n'))
        if (line.isNotEmpty) _parsePortLine(line),
    ];
  }

  @override
  Future<SerialPortInfo?> requestPort({
    List<SerialPortFilter> filters = const [],
    bool Function(SerialPortInfo port)? where,
  }) async {
    for (final port in await listPorts()) {
      final matches =
          filters.isEmpty ||
          filters.any(
            (f) =>
                (f.usbVendorId == null || f.usbVendorId == port.vendorId) &&
                (f.usbProductId == null || f.usbProductId == port.productId),
          );
      if (matches && (where == null || where(port))) {
        return port;
      }
    }
    return null;
  }

  @override
  Future<SerialTransport> open(SerialPortInfo port, {int? baudRate}) {
    _checkSupported();
    return NativeSerialTransport.open(port.id, baudRate: baudRate);
  }

  void _checkSupported() {
    if (!isSupported) {
      throw UnsupportedError(
        'Native serial ports are only supported on Linux, macOS and Windows. '
        'Provide a SerialTransport on ${Platform.operatingSystem}.',
      );
    }
  }
}

String _listPortsSync() {
  var size = 4096;
  while (true) {
    final buf = calloc<Char>(size);
    try {
      final needed = hss.hss_list_ports(buf, size);
      if (needed < 0) throw const SerialException('Failed to list ports');
      if (needed <= size) return buf.cast<Utf8>().toDartString();
      size = needed;
    } finally {
      calloc.free(buf);
    }
  }
}

SerialPortInfo _parsePortLine(String line) {
  final f = line.split('\t');
  String field(int i) => i < f.length ? f[i] : '';
  return SerialPortInfo(
    id: field(0),
    description: field(1),
    vendorId: int.tryParse(field(2), radix: 16),
    productId: int.tryParse(field(3), radix: 16),
    product: field(4).isEmpty ? null : field(4),
  );
}

/// A serial port opened through the native shim.
///
/// Blocking reads run on a dedicated isolate, which also performs writes, so
/// the calling isolate (e.g. a Flutter UI) is never blocked.
class NativeSerialTransport implements SerialTransport {
  final String path;
  final SendPort _toIo;
  final ReceivePort _fromIo;
  final StreamController<Uint8List> _input;
  final Completer<void> _closed = Completer<void>();
  final Map<int, Completer<void>> _pendingWrites = {};
  int _nextWriteId = 0;
  bool _closing = false;

  NativeSerialTransport._(this.path, this._toIo, this._fromIo, this._input);

  /// Open the serial port at [path] (e.g. `/dev/ttyACM0` or `COM3`), at
  /// [baudRate] if given.
  static Future<NativeSerialTransport> open(
    String path, {
    int? baudRate,
  }) async {
    final fromIo = ReceivePort('serial $path');
    final messages = StreamIterator(fromIo);
    try {
      await Isolate.spawn(_ioMain, (
        fromIo.sendPort,
        path,
        baudRate ?? 0,
      ), debugName: 'serial $path');
    } catch (_) {
      fromIo.close();
      rethrow;
    }
    if (!await messages.moveNext()) {
      throw SerialException('Serial I/O isolate exited for $path');
    }
    final first = messages.current as List<Object?>;
    if (first[0] != 'opened') {
      fromIo.close();
      throw SerialException(first[1] as String);
    }
    final input = StreamController<Uint8List>();
    final transport = NativeSerialTransport._(
      path,
      first[1] as SendPort,
      fromIo,
      input,
    );
    transport._listen(messages);
    return transport;
  }

  Future<void> _listen(StreamIterator<Object?> messages) async {
    while (await messages.moveNext()) {
      final msg = messages.current as List<Object?>;
      switch (msg[0]) {
        case 'data':
          final data = (msg[1] as TransferableTypedData)
              .materialize()
              .asUint8List();
          if (!_input.isClosed) _input.add(data);
        case 'written':
          _pendingWrites.remove(msg[1] as int)?.complete();
        case 'writeError':
          _pendingWrites
              .remove(msg[1] as int)
              ?.completeError(SerialException(msg[2] as String));
        case 'error':
          if (!_input.isClosed) {
            _input.addError(SerialException(msg[1] as String));
          }
        case 'closed':
          _finish();
          return;
      }
    }
    _finish();
  }

  void _finish() {
    _fromIo.close();
    for (final w in _pendingWrites.values) {
      w.completeError(SerialException('Serial port $path closed'));
    }
    _pendingWrites.clear();
    if (!_input.isClosed) _input.close();
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> write(List<int> data) {
    if (_closing || _closed.isCompleted) {
      return Future.error(SerialException('Serial port $path is closed'));
    }
    final id = _nextWriteId++;
    final done = _pendingWrites[id] = Completer<void>();
    _toIo.send([
      'write',
      id,
      TransferableTypedData.fromList([
        data is Uint8List ? data : Uint8List.fromList(data),
      ]),
    ]);
    return done.future;
  }

  @override
  Future<void> close() async {
    if (!_closing && !_closed.isCompleted) {
      _closing = true;
      _toIo.send(const ['close']);
    }
    await _closed.future.timeout(
      const Duration(seconds: 3),
      onTimeout: _finish,
    );
  }
}

/// Entry point of the I/O isolate: opens the port, then alternates between
/// reads (with a short timeout) and handling write/close requests.
Future<void> _ioMain((SendPort, String, int) args) async {
  final (toMain, path, baud) = args;
  final err = calloc<Char>(_errLen);
  String error() => err.cast<Utf8>().toDartString();

  final nativePath = path.toNativeUtf8();
  final handle = hss.hss_open_baud(nativePath.cast(), baud, err, _errLen);
  calloc.free(nativePath);
  if (handle == hss.HSS_INVALID_HANDLE) {
    toMain.send(['failed', error()]);
    calloc.free(err);
    return;
  }

  final inbox = ReceivePort();
  toMain.send(['opened', inbox.sendPort]);

  var closing = false;
  var failed = false;
  inbox.listen((Object? message) {
    final msg = message as List<Object?>;
    switch (msg[0]) {
      case 'write':
        final id = msg[1] as int;
        final data = (msg[2] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final buf = malloc<Uint8>(data.isEmpty ? 1 : data.length);
        buf.asTypedList(data.length).setAll(0, data);
        final n = hss.hss_write(handle, buf, data.length, err, _errLen);
        malloc.free(buf);
        toMain.send(n < 0 ? ['writeError', id, error()] : ['written', id]);
      case 'close':
        closing = true;
    }
  });

  final buf = malloc<Uint8>(_readBufferSize);
  while (!closing && !failed) {
    final n = hss.hss_read(
      handle,
      buf,
      _readBufferSize,
      _readTimeoutMs,
      err,
      _errLen,
    );
    if (n > 0) {
      toMain.send([
        'data',
        TransferableTypedData.fromList([buf.asTypedList(n)]),
      ]);
    } else if (n < 0) {
      toMain.send(['error', error()]);
      failed = true;
    }
    // Let write and close requests in.
    await Future<void>.delayed(Duration.zero);
  }

  hss.hss_close(handle);
  malloc.free(buf);
  calloc.free(err);
  inbox.close();
  toMain.send(const ['closed']);
}
