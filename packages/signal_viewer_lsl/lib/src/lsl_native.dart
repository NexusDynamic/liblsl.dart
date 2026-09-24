import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';
import 'package:liblsl/lsl.dart';

import 'package:permission_handler/permission_handler.dart';

import 'lsl_types.dart';

LslBackend createBackend() => _NativeLsl();

/// liblsl through liblsl.dart. Inlets and outlets each run in their own
/// isolate (liblsl.dart's default), so nothing here blocks the UI.
class _NativeLsl implements LslBackend {
  @override
  bool get supported => true;

  @override
  String get version {
    final v = LSL.version;
    return '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
  }

  @override
  void configure(LslNetworkOptions o) {
    if (o.isDefault) return;
    LSL.setConfigContent(
      LSLApiConfig(
        knownPeers: o.knownPeers,
        sessionId: o.sessionId,
        resolveScope: ResolveScope.values.byName(o.scope.name),
        ipv6: o.ipv6 ? IPv6Mode.allow : IPv6Mode.disable,
      ),
    );
  }

  Future<void>? _prepared;

  @override
  Future<void> prepare() => _prepared ??= _prepare();

  Future<void> _prepare() async {
    if (!Platform.isAndroid) return;
    // Android 13+ asks for nearby Wi-Fi devices and 16+ for the local
    // network; older versions grant both with the manifest. Discovery
    // still works with known peers if they are refused.
    try {
      await [
        Permission.nearbyWifiDevices,
        Permission.accessLocalNetwork,
      ].request();
    } catch (_) {}
    // Without the lock, Android drops multicast packets (discovery).
    try {
      await FlutterMulticastLock().acquireMulticastLock(
        lockName: 'hyprview_lsl',
      );
    } catch (_) {}
  }

  @override
  double clock() => LSL.localClock();

  @override
  LslDiscovery discover() => _Discovery();

  @override
  Future<LslInlet> openInlet(
    LslStreamDescription stream,
    LslInletOptions options,
  ) async {
    final source = stream.handle;
    if (source is! LSLStreamInfo || source.destroyed) {
      throw StateError('${stream.name} is no longer on the network');
    }
    // The inlet gets its own copy: the discovery's may be freed any time.
    final info = source.copy();
    final LSLInlet inlet;
    try {
      inlet = await LSL.createInlet<dynamic>(
        streamInfo: info,
        maxBuffer: options.bufferS,
        chunkSize: options.chunkSize,
        recover: options.recover,
      );
    } catch (_) {
      info.destroy();
      rethrow;
    }
    final flags = {
      if (options.clockSync) LSLProcessingOptions.clockSync,
      if (options.dejitter) LSLProcessingOptions.dejitter,
      if (options.dejitter && options.monotonize)
        LSLProcessingOptions.monotonize,
    };
    if (flags.isNotEmpty) await inlet.setPostProcessing(flags);
    var channels = _defaultChannels(stream.channelCount);
    LSLStreamInfoWithMetadata? full;
    try {
      full = await inlet.getFullInfo(timeout: 5);
      channels = _channelsOf(full, stream.channelCount);
    } catch (_) {
      // No metadata (e.g. the outlet is gone again): default labels.
    }
    return _Inlet(stream, channels, inlet, [
      info,
      ?full,
    ], full == null ? '' : _xmlOf(full));
  }

  @override
  Future<LslOutlet> createOutlet(
    LslOutletSpec spec,
    LslOutletOptions options,
  ) async {
    final info = await LSL.createStreamInfo(
      streamName: spec.name,
      streamType: _contentType(spec.type),
      channelCount: spec.channelCount,
      sampleRate: spec.rate > 0 ? spec.rate : LSL_IRREGULAR_RATE,
      channelFormat: spec.format == LslFormat.string
          ? LSLChannelFormat.string
          : LSLChannelFormat.float32,
      sourceId: spec.sourceId,
    );
    final root = info.description.value;
    if (spec.channels.isNotEmpty) {
      final channels = root.addChildElement('channels');
      for (final c in spec.channels) {
        final ch = channels.addChildElement('channel');
        ch.addChildValue('label', c.label);
        if (c.unit.isNotEmpty) ch.addChildValue('unit', c.unit);
        if (c.type.isNotEmpty) ch.addChildValue('type', c.type);
      }
    }
    for (final g in spec.desc.entries) {
      final group = root.addChildElement(g.key);
      for (final e in g.value.entries) {
        if (e.value.isNotEmpty) group.addChildValue(e.key, e.value);
      }
    }
    try {
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        chunkSize: options.chunkSize,
        maxBuffer: options.bufferS,
        transportOptions: {
          // liblsl has no blocking transport for strings.
          if (options.syncBlocking && spec.format != LslFormat.string)
            LSLTransportOptions.syncBlocking,
        },
      );
      return _Outlet(spec, outlet, info);
    } catch (_) {
      info.destroy();
      rethrow;
    }
  }
}

/// liblsl.dart's type for [type]: a standard one if there is one.
LSLContentType _contentType(String type) =>
    LSLContentType.values.where((t) => t.value == type).firstOrNull ??
    LSLContentType.custom(type);

List<LslChannel> _defaultChannels(int n) => [
  for (var i = 0; i < n; i++) LslChannel('ch${i + 1}'),
];

/// Labels, units and types from `<desc><channels><channel>`, as the Python
/// viewer reads them.
List<LslChannel> _channelsOf(LSLStreamInfoWithMetadata info, int n) {
  final out = <LslChannel>[];
  final channels = info.description.value.childNamed('channels');
  var ch = channels?.childNamed('channel');
  String value(LSLXmlNode node, String name) =>
      node.childValueNamed(name).trim();

  while (ch != null && !ch.isEmpty() && out.length < n) {
    final label = value(ch, 'label');
    out.add(
      LslChannel(
        label.isEmpty ? 'ch${out.length + 1}' : label,
        unit: value(ch, 'unit'),
        type: value(ch, 'type'),
      ),
    );
    ch = ch.nextSiblingNamed('channel');
  }
  return [
    ...out,
    for (var i = out.length; i < n; i++) LslChannel('ch${i + 1}'),
  ];
}

LslFormat _format(LSLChannelFormat f) => switch (f) {
  LSLChannelFormat.float32 => LslFormat.float32,
  LSLChannelFormat.double64 => LslFormat.double64,
  LSLChannelFormat.int8 => LslFormat.int8,
  LSLChannelFormat.int16 => LslFormat.int16,
  LSLChannelFormat.int32 => LslFormat.int32,
  LSLChannelFormat.int64 => LslFormat.int64,
  LSLChannelFormat.string => LslFormat.string,
  LSLChannelFormat.undefined => LslFormat.undefined,
};

String _xmlOf(LSLStreamInfo s) {
  try {
    return s.toXml();
  } catch (_) {
    return '';
  }
}

LslStreamDescription _describe(LSLStreamInfo s) => LslStreamDescription(
  name: s.streamName,
  type: s.streamType.value,
  channelCount: s.channelCount,
  rate: s.sampleRate == LSL_IRREGULAR_RATE ? 0 : s.sampleRate,
  format: _format(s.channelFormat),
  sourceId: s.sourceId,
  hostname: s.hostname ?? '',
  uid: s.uid ?? '',
  xml: _xmlOf(s),
  handle: s,
);

/// A continuous resolver: liblsl looks for streams in the background, and
/// [streams] only reads what it found.
class _Discovery implements LslDiscovery {
  final _resolver = LSLStreamResolverContinuous(forgetAfter: 5, maxStreams: 256)
    ..create();

  /// Stream infos by uid, kept until the stream disappears so that a
  /// description handed out stays valid while it is listed.
  final Map<String, LSLStreamInfo> _known = {};
  bool _closed = false;

  @override
  Future<List<LslStreamDescription>> streams() async {
    if (_closed) return const [];
    final found = await _resolver.resolve();
    final seen = <String>{};
    for (final s in found) {
      final uid = s.uid ?? '';
      if (_closed || !seen.add(uid) || _known.containsKey(uid)) {
        s.destroy();
      } else {
        _known[uid] = s;
      }
    }
    for (final uid in [..._known.keys]) {
      if (!seen.contains(uid)) _known.remove(uid)!.destroy();
    }
    return [for (final s in _known.values) _describe(s)];
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final s in _known.values) {
      s.destroy();
    }
    _known.clear();
    _resolver.destroy();
  }
}

class _Inlet implements LslInlet {
  @override
  final LslStreamDescription stream;
  @override
  final List<LslChannel> channels;
  final LSLInlet _inlet;
  final List<LSLStreamInfo> _infos;
  bool _closed = false;

  @override
  final String fullXml;

  _Inlet(this.stream, this.channels, this._inlet, this._infos, this.fullXml);

  @override
  Future<double> timeCorrection() => _inlet.getTimeCorrection(timeout: 2);

  @override
  Future<LslChunk> pull(int maxSamples) async {
    if (_closed) return LslChunk.empty;
    if (stream.format.isString) {
      final c = await _inlet.pullChunk(maxSamples: maxSamples);
      if (c.isEmpty) return LslChunk.empty;
      return LslChunk(
        Float64List.fromList(c.timestamps),
        strings: [
          for (final s in c.samples)
            for (final v in s) '$v',
        ],
      );
    }
    final c = await _inlet.pullChunkTyped(maxSamples: maxSamples);
    if (c.isEmpty) return LslChunk.empty;
    final data = c.data;
    final List<double> values;
    if (data is Float32List || data is Float64List) {
      values = data as List<double>;
    } else {
      // Integers as doubles (exact up to 2^53).
      final n = c.sampleCount * c.channelCount;
      final f = Float64List(n);
      final src = data as List<num>;
      for (var i = 0; i < n; i++) {
        f[i] = src[i].toDouble();
      }
      values = f;
    }
    return LslChunk(c.timestamps, values: values);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inlet.destroy();
    for (final i in _infos) {
      i.destroy();
    }
  }
}

class _Outlet implements LslOutlet {
  @override
  final LslOutletSpec spec;
  final LSLOutlet _outlet;
  final LSLStreamInfo _info;
  bool _closed = false;

  _Outlet(this.spec, this._outlet, this._info);

  @override
  Future<void> push(Float32List values, Float64List times) async {
    if (_closed || times.isEmpty) return;
    await _outlet.pushChunkTyped(values, timestamps: times);
  }

  @override
  Future<void> pushStrings(List<String> values, List<double> times) async {
    if (_closed || values.isEmpty) return;
    await _outlet.pushChunk([
      for (final v in values) [v],
    ], timestamps: times);
  }

  @override
  Future<bool> hasConsumers() async => !_closed && await _outlet.hasConsumers();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _outlet.destroy();
    _info.destroy();
  }
}
