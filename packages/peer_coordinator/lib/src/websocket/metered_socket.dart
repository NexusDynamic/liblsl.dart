/// A byte budget beneath a WebSocket. `dart:io` only: used by the hub.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How many bytes a peer may send on one connection: a burst of [capacity],
/// refilled at [perSecond].
class ByteBudget {
  ByteBudget({required this.capacity, required this.perSecond})
    : _tokens = capacity.toDouble();

  final int capacity;
  final int perSecond;

  double _tokens;
  final Stopwatch _clock = Stopwatch()..start();

  /// Spend [bytes]; false once the budget is exhausted.
  bool take(int bytes) {
    final elapsed = _clock.elapsedMicroseconds / 1e6;
    _clock.reset();
    _tokens = (_tokens + elapsed * perSecond).clamp(0, capacity.toDouble());
    _tokens -= bytes;
    return _tokens >= 0;
  }
}

/// A [Socket] whose inbound bytes are charged to a [ByteBudget], destroyed
/// when the budget runs out. Everything else is delegated.
///
/// `dart:io` bounds each WebSocket frame (`maxPayloadLength`) but buffers a
/// fragmented message until its final frame, so a peer streaming small
/// non-final frames could make the hub hold an unbounded message. Metering
/// the raw bytes bounds that whatever the framing.
class MeteredSocket extends Stream<Uint8List> implements Socket {
  MeteredSocket(this._socket, this._budget, {this.onExceeded});

  final Socket _socket;
  final ByteBudget _budget;

  /// Called once, just before the socket is destroyed for exceeding.
  final void Function()? onExceeded;
  bool _exceeded = false;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket.listen(
    (chunk) {
      if (_exceeded) return;
      if (!_budget.take(chunk.length)) {
        _exceeded = true;
        onExceeded?.call();
        _socket.destroy();
        return;
      }
      onData?.call(chunk);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> close() => _socket.close();
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> flush() => _socket.flush();
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
  @override
  InternetAddress get address => _socket.address;
  @override
  int get port => _socket.port;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
  @override
  int get remotePort => _socket.remotePort;
  @override
  void destroy() => _socket.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
}
