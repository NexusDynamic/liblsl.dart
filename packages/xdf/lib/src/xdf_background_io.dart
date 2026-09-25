import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:signal_core/signal_core.dart';

import 'stream_info.dart';
import 'xdf_file.dart';
import 'xdf_source.dart';

const bool isolatesSupported = true;

/// A stream as the background isolate last reported it.
class _StreamState implements XdfStreamView {
  @override
  final int slot;
  @override
  final int id;
  final String xml;
  @override
  final bool regular;
  @override
  final int sampleCount;
  @override
  final int channelCount;
  @override
  final num samplingRate;
  @override
  final double t0;
  @override
  final double t1;

  /// Events of an irregular stream, when they changed.
  final XdfEvents? events;

  XdfStreamInfo? _info;

  _StreamState(
    this.slot,
    this.id,
    this.xml,
    this.regular,
    this.sampleCount,
    this.channelCount,
    this.samplingRate,
    this.t0,
    this.t1,
    this.events,
  );

  @override
  XdfStreamInfo get info => _info ??= XdfStreamInfo.parse(xml);
}

/// What the background isolate reports while indexing.
class _Snapshot {
  final List<_StreamState> streams;
  final double duration;
  final double origin;
  final double progress;
  final bool complete;

  const _Snapshot(
    this.streams,
    this.duration,
    this.origin,
    this.progress,
    this.complete,
  );
}

// Messages from the isolate.
const _tSendPort = 0;
const _tSnapshot = 1;
const _tResult = 2;
const _tError = 3;
const _tDerived = 4;
const _tOpenError = 5;
const _tIndexError = 6;

// Messages to the isolate.
const _tEnvelope = 10;
const _tRead = 11;
const _tClose = 12;

/// Open an [XdfFile] in a new isolate and return a proxy for it.
Future<XdfRecordingSource> openInIsolate(
  ByteSourceSpec spec,
  XdfFileOptions options,
) async {
  final fromIsolate = ReceivePort();
  final exit = ReceivePort();
  final isolate = await Isolate.spawn(
    _main,
    (fromIsolate.sendPort, spec, options),
    debugName: 'XdfFile',
    onExit: exit.sendPort,
    onError: fromIsolate.sendPort,
  );
  final proxy = _XdfProxy(isolate, fromIsolate, exit);
  await proxy._ready.future;
  return proxy;
}

Future<void> _main((SendPort, ByteSourceSpec, XdfFileOptions) args) async {
  final (toMain, spec, options) = args;
  final inbox = ReceivePort();
  toMain.send((_tSendPort, inbox.sendPort));
  final XdfFile file;
  try {
    file = await XdfFile.open(spec.open(), options: options);
  } catch (e) {
    toMain.send((_tOpenError, e.toString()));
    inbox.close();
    return;
  }
  // Events are sent again only when they grew.
  final sentEvents = <int, int>{};
  _Snapshot snapshot() => _Snapshot(
    [
      for (final s in file.streams)
        _StreamState(
          s.slot,
          s.id,
          s.info.toXmlString(),
          s.regular,
          s.sampleCount,
          s.channelCount,
          s.samplingRate,
          s.t0,
          s.t1,
          !s.regular && sentEvents[s.slot] != s.sampleCount
              ? (() {
                  sentEvents[s.slot] = s.sampleCount;
                  return file.events(s.slot);
                })()
              : null,
        ),
    ],
    file.duration,
    file.origin,
    file.progress,
    file.complete,
  );
  toMain.send((_tSnapshot, snapshot()));
  file.onIndex.listen(
    (_) => toMain.send((_tSnapshot, snapshot())),
    onError: (Object e) => toMain.send((_tIndexError, e.toString())),
  );
  file.onDerivedProgress.listen((p) => toMain.send((_tDerived, p)));

  await for (final message in inbox) {
    final (int tag, int id, Object? request) = message as (int, int, Object?);
    void reply(Future<Object?> f) => f.then(
      (r) => toMain.send((_tResult, id, r)),
      onError: (Object e) => toMain.send((_tError, id, e.toString())),
    );
    switch (tag) {
      case _tEnvelope:
        reply(file.envelope(request! as EnvelopeRequest));
      case _tRead:
        reply(file.read(request! as ReadRequest));
      case _tClose:
        await file.close();
        inbox.close();
        toMain.send((_tResult, id, null));
    }
  }
}

class _XdfProxy implements XdfRecordingSource {
  final Isolate _isolate;
  final ReceivePort _fromIsolate;
  final ReceivePort _exit;
  SendPort? _toIsolate;
  final _ready = Completer<void>();
  final _indexed = Completer<void>();
  final _index = StreamController<void>.broadcast();
  final _derived = StreamController<DerivedProgress>.broadcast();
  final Map<int, Completer<Object?>> _calls = {};
  int _nextId = 0;
  _Snapshot _snapshot = const _Snapshot([], 0, 0, 0, false);
  final Map<int, XdfEvents> _events = {};
  bool _closed = false;

  _XdfProxy(this._isolate, this._fromIsolate, this._exit) {
    _fromIsolate.listen(_onMessage);
    _exit.listen((_) => _fail('XdfFile isolate exited'));
  }

  void _onMessage(Object? message) {
    if (message is List) {
      // An uncaught error: [error, stack].
      _fail('XdfFile isolate error: ${message.first}');
      return;
    }
    final m = message! as Record;
    switch (m) {
      case (_tSendPort, final SendPort port):
        _toIsolate = port;
      case (_tOpenError, final String error):
        if (!_ready.isCompleted) _ready.completeError(FormatException(error));
        _shutDown();
      case (_tSnapshot, final _Snapshot s):
        _snapshot = s;
        for (final st in s.streams) {
          if (st.events != null) _events[st.slot] = st.events!;
        }
        if (!_ready.isCompleted) _ready.complete();
        if (s.complete && !_indexed.isCompleted) _indexed.complete();
        if (!_index.isClosed) _index.add(null);
      case (_tIndexError, final String error):
        if (!_indexed.isCompleted) _indexed.completeError(error);
        if (!_index.isClosed) _index.addError(error);
      case (_tDerived, final DerivedProgress p):
        if (!_derived.isClosed) _derived.add(p);
      case (_tResult, final int id, final Object? result):
        _calls.remove(id)?.complete(result);
      case (_tError, final int id, final String error):
        _calls.remove(id)?.completeError(StateError(error));
    }
  }

  void _fail(String error) {
    if (!_ready.isCompleted) _ready.completeError(StateError(error));
    for (final c in _calls.values) {
      c.completeError(StateError(error));
    }
    _calls.clear();
    _shutDown();
  }

  void _shutDown() {
    _fromIsolate.close();
    _exit.close();
    _index.close();
    _derived.close();
  }

  Future<Object?> _call(int tag, Object? request) {
    if (_closed || _toIsolate == null) {
      return Future.error(StateError('XdfFile is closed'));
    }
    final id = _nextId++;
    final c = _calls[id] = Completer<Object?>();
    _toIsolate!.send((tag, id, request));
    return c.future;
  }

  @override
  List<XdfStreamView> get streams => _snapshot.streams;

  @override
  double get duration => _snapshot.duration;

  @override
  double get origin => _snapshot.origin;

  @override
  bool get complete => _snapshot.complete;

  @override
  double get progress => _snapshot.progress;

  @override
  Stream<void> get onIndex => _index.stream;

  @override
  Future<void> get indexed => _indexed.future;

  @override
  Stream<DerivedProgress> get onDerivedProgress => _derived.stream;

  @override
  Future<Envelope> envelope(EnvelopeRequest request) async =>
      (await _call(_tEnvelope, request))! as Envelope;

  @override
  Future<SignalWindow> read(ReadRequest request) async =>
      (await _call(_tRead, request))! as SignalWindow;

  @override
  XdfEvents events(int slot) {
    final s = _snapshot.streams[slot];
    if (s.regular) throw ArgumentError('Stream $slot is regular');
    return _events[slot] ?? XdfEvents(Float64List(0), const [], null);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    try {
      await _call(_tClose, null).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Gone already.
    }
    _closed = true;
    _isolate.kill();
    _shutDown();
  }
}
