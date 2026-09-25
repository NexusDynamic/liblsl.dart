import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:xdf/xdf.dart';

/// An open .xdf recording: a tab per stream (streams of an XDF file each
/// have their own clock, so they are never merged).
class XdfSession extends SourceSession {
  final String name;

  /// Path on disk (desktop and mobile), for recent files.
  final String? path;

  /// The recording, indexed in a background isolate where possible.
  final XdfRecordingSource file;
  late final StreamSubscription<void> _indexSub;
  late final StreamSubscription<DerivedProgress> _derivedSub;
  double? _derivedProgress;
  bool _closed = false;

  XdfSession._(this.name, this.path, this.file) {
    _indexSub = file.onIndex.listen(
      (_) => notifyListeners(),
      onError: (Object e) {
        error = '$e';
        notifyListeners();
      },
    );
    _derivedSub = file.onDerivedProgress.listen((p) {
      _derivedProgress = p.done ? null : p.progress;
      notifyListeners();
    });
  }

  /// Why indexing failed, if it did.
  String? error;

  static Future<XdfSession> open(
    String name,
    ByteSourceSpec spec, {
    String? path,
    int? cacheBytes,
  }) async {
    final file = await XdfFile.openInBackground(
      spec,
      options: cacheBytes == null
          ? const XdfFileOptions()
          : XdfFileOptions(cacheBytes: cacheBytes),
    );
    return XdfSession._(name, path, file);
  }

  double? get derivedProgress => _derivedProgress;

  /// The stream key that the source setup of [s] is saved under: the same
  /// stream in other recordings (and live over LSL, by name and type) gets
  /// the same setup.
  static String keyOf(XdfStreamInfo s) => 'xdf:${s.name}|${s.type}';

  /// One stream per XDF stream with samples.
  @override
  List<StreamInfo> get streams => [
    for (final s in file.streams)
      if (s.sampleCount > 0) _info(s),
  ];

  static StreamInfo _info(XdfStreamView s) {
    final i = s.info;
    final n = i.channelCount;
    return StreamInfo(
      key: keyOf(i),
      name: i.name.isEmpty ? 'Stream ${s.id}' : i.name,
      type: i.type,
      kind: i.format.isString ? Kind.event : kindFromType(i.type),
      rate: s.regular ? i.nominalRate : 0,
      labels: [for (var c = 0; c < n; c++) i.label(c)],
      units: [for (var c = 0; c < n; c++) i.unit(c)],
      channels: [for (var c = 0; c < n; c++) ChannelRef(s.slot, c)],
    );
  }

  XdfStreamView streamOf(StreamInfo info) =>
      file.streams[info.channels.first.stream];

  @override
  String get label => name;

  @override
  String get tooltip => path ?? name;

  @override
  bool get groupable => false;

  @override
  bool get replayable => true;

  @override
  String get rememberKey => 'xdf:$name';

  @override
  double? get progress => file.complete ? null : file.progress;

  @override
  bool get closed => _closed;

  @override
  bool decodable(StreamInfo info) => !streamOf(info).info.format.isString;

  @override
  StreamSource sourceFor(StreamInfo info) => XdfStreamSource(this, info);

  @override
  String describe() {
    if (error != null) return '$name: $error';
    if (!file.complete) {
      return '$name: indexing ${(file.progress * 100).toStringAsFixed(0)}%';
    }
    final withData = file.streams.where((s) => s.sampleCount > 0).length;
    return [
      name,
      '$withData stream${withData == 1 ? '' : 's'}',
      '${file.duration.toStringAsFixed(1)} s',
    ].join(' · ');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _indexSub.cancel();
    await _derivedSub.cancel();
    await file.close();
  }
}

/// One tab's view of a stream of an XDF recording.
class XdfStreamSource implements StreamSource {
  final XdfSession session;
  @override
  final StreamInfo info;

  XdfStreamSource(this.session, this.info);

  XdfStreamView get _stream => session.streamOf(info);

  @override
  bool get live => false;

  @override
  Listenable get changes => session;

  @override
  double? get derivedProgress => session.derivedProgress;

  @override
  bool get indexing => !session.file.complete;

  @override
  double get start => info.irregular ? 0 : _stream.t0;

  @override
  double get end => session.file.duration;

  @override
  Future<Envelope?> envelope(
    double t0,
    double t1,
    int bins,
    DerivedSpec derived, {
    bool binStats = false,
  }) async {
    if (info.irregular || session.closed) return null;
    return session.file.envelope(
      EnvelopeRequest(
        channels: info.channels,
        t0: t0,
        t1: t1,
        bins: bins,
        derived: derived,
        binStats: binStats,
      ),
    );
  }

  @override
  Future<SignalWindow?> read(double t0, double t1, DerivedSpec derived) async {
    if (info.irregular || session.closed) return null;
    return session.file.read(
      ReadRequest(channels: info.channels, t0: t0, t1: t1, derived: derived),
    );
  }

  @override
  EventSamples events() {
    final s = _stream;
    if (s.regular) return EventSamples.empty;
    final e = session.file.events(s.slot);
    return EventSamples(
      e.times,
      e.channels,
      text: e.strings,
      markers: s.info.format.isString,
    );
  }
}
