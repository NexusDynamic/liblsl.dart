import 'dart:typed_data';

/// Sample format of an LSL stream.
enum LslFormat {
  float32,
  double64,
  int8,
  int16,
  int32,
  int64,
  string,
  undefined;

  bool get isString => this == string;
}

/// A stream found on the network.
class LslStreamDescription {
  final String name;
  final String type;
  final int channelCount;

  /// Nominal sampling rate in Hz, 0 for irregular streams.
  final double rate;
  final LslFormat format;
  final String sourceId;
  final String hostname;
  final String uid;

  /// The stream's info as LSL gives it on discovery (`info` XML: name,
  /// type, host, session, created_at and so on; `desc` may be empty until
  /// an inlet asks for the full info).
  final String xml;

  /// The backend's native stream info.
  final Object? handle;

  const LslStreamDescription({
    required this.name,
    required this.type,
    required this.channelCount,
    required this.rate,
    required this.format,
    this.sourceId = '',
    this.hostname = '',
    this.uid = '',
    this.xml = '',
    this.handle,
  });

  /// Identifies the stream across restarts of its outlet (as the Python
  /// viewer does).
  String get key => 'lsl:${sourceId.isEmpty ? uid : sourceId}:$name';

  String get summary =>
      '$type, $channelCount ch, '
      '${rate > 0 ? '${_num(rate)} Hz' : 'irregular'}, ${format.name}'
      '${hostname.isEmpty ? '' : ' · $hostname'}';
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Description of one channel, from a stream's metadata.
class LslChannel {
  final String label;
  final String unit;
  final String type;

  const LslChannel(this.label, {this.unit = '', this.type = ''});
}

/// Samples pulled from an inlet, sample-major.
class LslChunk {
  /// Time stamp of each sample, in seconds on the LSL clock.
  final Float64List times;

  /// `times.length * channelCount` values (numeric streams).
  final Float32List? values;

  /// `times.length * channelCount` strings (string streams).
  final List<String>? strings;

  const LslChunk(this.times, {this.values, this.strings});

  int get length => times.length;

  static final empty = LslChunk(Float64List(0));
}

/// A connected inlet.
abstract class LslInlet {
  LslStreamDescription get stream;

  /// Channel descriptions from the stream's metadata (labels default to
  /// `ch1`, `ch2`...).
  List<LslChannel> get channels;

  /// Everything buffered, up to [maxSamples]. Does not wait.
  Future<LslChunk> pull(int maxSamples);

  /// The stream's full info (`info` XML with `desc`), or empty if the
  /// sender did not give it.
  String get fullXml;

  /// The current clock offset: add it to the sender's time stamps to get
  /// this computer's LSL clock.
  Future<double> timeCorrection();

  Future<void> close();
}

/// What an outlet publishes.
class LslOutletSpec {
  final String name;
  final String type;
  final int channelCount;

  /// Hz, or 0 for irregular.
  final double rate;

  /// [LslFormat.float32] or [LslFormat.string].
  final LslFormat format;
  final String sourceId;
  final List<LslChannel> channels;

  /// Extra metadata: `<desc><group><key>value</key></group></desc>`.
  final Map<String, Map<String, String>> desc;

  const LslOutletSpec({
    required this.name,
    required this.type,
    required this.channelCount,
    required this.rate,
    this.format = LslFormat.float32,
    required this.sourceId,
    this.channels = const [],
    this.desc = const {},
  });
}

/// A published stream.
abstract class LslOutlet {
  LslOutletSpec get spec;

  /// Push `times.length` samples from [values] (sample-major), stamped with
  /// [times] on the LSL clock.
  Future<void> push(Float32List values, Float64List times);

  /// Push samples of a single-channel string stream: [values][i] stamped
  /// with [times][i] on the LSL clock.
  Future<void> pushStrings(List<String> values, List<double> times);

  Future<bool> hasConsumers();

  Future<void> close();
}

/// Streams on the network, updated in the background while open.
abstract class LslDiscovery {
  /// Streams seen recently.
  Future<List<LslStreamDescription>> streams();

  void close();
}

/// Access to LSL, or its absence (web).
abstract class LslBackend {
  bool get supported;

  /// liblsl's version, e.g. `1.18`.
  String get version;

  /// Network configuration; only takes effect before any other LSL call.
  void configure(LslNetworkOptions options);

  /// Ask for what LSL needs on this platform (Android: local network
  /// permissions and a Wi-Fi multicast lock). Called before LSL is first
  /// used, so people who never use it are never asked.
  Future<void> prepare();

  /// Seconds on the LSL clock.
  double clock();

  LslDiscovery discover();

  Future<LslInlet> openInlet(
    LslStreamDescription stream,
    LslInletOptions options,
  );

  Future<LslOutlet> createOutlet(LslOutletSpec spec, LslOutletOptions options);
}

// -- options ------------------------------------------------------------------

/// How streams are received. The defaults suit a viewer; see the LSL
/// settings dialog for what each does.
class LslInletOptions {
  /// Seconds of data liblsl buffers if the app falls behind.
  final int bufferS;

  /// Samples per network packet the sender is asked for; 0 lets the sender
  /// decide. Larger chunks reduce CPU load at the cost of latency.
  final int chunkSize;

  /// How often buffered samples are collected, in ms.
  final int pullIntervalMs;

  /// Translate time stamps to this computer's clock.
  final bool clockSync;

  /// Smooth time stamp jitter.
  final bool dejitter;

  /// Force time stamps to increase (with dejitter).
  final bool monotonize;

  /// Reconnect automatically when a stream comes back.
  final bool recover;

  const LslInletOptions({
    this.bufferS = 30,
    this.chunkSize = 0,
    this.pullIntervalMs = 20,
    this.clockSync = true,
    this.dejitter = true,
    this.monotonize = false,
    this.recover = true,
  });

  LslInletOptions copyWith({
    int? bufferS,
    int? chunkSize,
    int? pullIntervalMs,
    bool? clockSync,
    bool? dejitter,
    bool? monotonize,
    bool? recover,
  }) => LslInletOptions(
    bufferS: bufferS ?? this.bufferS,
    chunkSize: chunkSize ?? this.chunkSize,
    pullIntervalMs: pullIntervalMs ?? this.pullIntervalMs,
    clockSync: clockSync ?? this.clockSync,
    dejitter: dejitter ?? this.dejitter,
    monotonize: monotonize ?? this.monotonize,
    recover: recover ?? this.recover,
  );

  Map<String, Object?> toJson() => {
    'buffer_s': bufferS,
    'chunk_size': chunkSize,
    'pull_interval_ms': pullIntervalMs,
    'clock_sync': clockSync,
    'dejitter': dejitter,
    'monotonize': monotonize,
    'recover': recover,
  };

  factory LslInletOptions.fromJson(Map<String, Object?> j) {
    const d = LslInletOptions();
    return LslInletOptions(
      bufferS: _int(j['buffer_s'], d.bufferS, 1, 3600),
      chunkSize: _int(j['chunk_size'], d.chunkSize, 0, 100000),
      pullIntervalMs: _int(j['pull_interval_ms'], d.pullIntervalMs, 1, 1000),
      clockSync: _bool(j['clock_sync'], d.clockSync),
      dejitter: _bool(j['dejitter'], d.dejitter),
      monotonize: _bool(j['monotonize'], d.monotonize),
      recover: _bool(j['recover'], d.recover),
    );
  }
}

/// How streams are published (device forwarding and recording replay).
class LslOutletOptions {
  /// Seconds of data an outlet keeps for a slow consumer.
  final int bufferS;

  /// Samples per network packet; 0 sends each push as it comes.
  final int chunkSize;

  /// How long samples are collected before they are pushed, in ms. Fewer,
  /// larger pushes use less CPU; consumers see up to this much extra
  /// latency.
  final int pushIntervalMs;

  /// Zero-copy blocking sends (less CPU for high-bandwidth streams; a slow
  /// consumer holds up the push). Not used for string streams.
  final bool syncBlocking;

  const LslOutletOptions({
    this.bufferS = 60,
    this.chunkSize = 0,
    this.pushIntervalMs = 20,
    this.syncBlocking = false,
  });

  LslOutletOptions copyWith({
    int? bufferS,
    int? chunkSize,
    int? pushIntervalMs,
    bool? syncBlocking,
  }) => LslOutletOptions(
    bufferS: bufferS ?? this.bufferS,
    chunkSize: chunkSize ?? this.chunkSize,
    pushIntervalMs: pushIntervalMs ?? this.pushIntervalMs,
    syncBlocking: syncBlocking ?? this.syncBlocking,
  );

  Map<String, Object?> toJson() => {
    'buffer_s': bufferS,
    'chunk_size': chunkSize,
    'push_interval_ms': pushIntervalMs,
    'sync_blocking': syncBlocking,
  };

  factory LslOutletOptions.fromJson(Map<String, Object?> j) {
    const d = LslOutletOptions();
    return LslOutletOptions(
      bufferS: _int(j['buffer_s'], d.bufferS, 1, 3600),
      chunkSize: _int(j['chunk_size'], d.chunkSize, 0, 100000),
      pushIntervalMs: _int(j['push_interval_ms'], d.pushIntervalMs, 1, 1000),
      syncBlocking: _bool(j['sync_blocking'], d.syncBlocking),
    );
  }
}

/// How far discovery reaches.
enum LslScope { machine, link, site, organization, global }

/// Network setup, applied when the app starts.
class LslNetworkOptions {
  /// Addresses or host names to look for streams on directly, for networks
  /// that block multicast.
  final List<String> knownPeers;

  /// Only streams with the same session id see each other.
  final String sessionId;
  final LslScope scope;
  final bool ipv6;

  const LslNetworkOptions({
    this.knownPeers = const [],
    this.sessionId = 'default',
    this.scope = LslScope.site,
    this.ipv6 = true,
  });

  bool get isDefault =>
      knownPeers.isEmpty &&
      sessionId == 'default' &&
      scope == LslScope.site &&
      ipv6;

  @override
  bool operator ==(Object other) =>
      other is LslNetworkOptions &&
      other.sessionId == sessionId &&
      other.scope == scope &&
      other.ipv6 == ipv6 &&
      other.knownPeers.join('\n') == knownPeers.join('\n');

  @override
  int get hashCode => Object.hash(sessionId, scope, ipv6, knownPeers.join());

  Map<String, Object?> toJson() => {
    'known_peers': knownPeers,
    'session_id': sessionId,
    'scope': scope.name,
    'ipv6': ipv6,
  };

  factory LslNetworkOptions.fromJson(Map<String, Object?> j) {
    const d = LslNetworkOptions();
    final peers = j['known_peers'];
    final scope = j['scope'];
    final session = j['session_id'];
    return LslNetworkOptions(
      knownPeers: peers is List
          ? [
              for (final p in peers)
                if (p is String && p.trim().isNotEmpty) p.trim(),
            ]
          : d.knownPeers,
      sessionId: session is String && session.trim().isNotEmpty
          ? session.trim()
          : d.sessionId,
      scope: LslScope.values.asNameMap()[scope] ?? d.scope,
      ipv6: _bool(j['ipv6'], d.ipv6),
    );
  }
}

/// All LSL settings (Preferences).
class LslOptions {
  final LslInletOptions inlet;
  final LslOutletOptions outlet;
  final LslNetworkOptions network;

  /// Start a replay over again when it reaches the end.
  final bool replayLoop;

  const LslOptions({
    this.inlet = const LslInletOptions(),
    this.outlet = const LslOutletOptions(),
    this.network = const LslNetworkOptions(),
    this.replayLoop = false,
  });

  LslOptions copyWith({
    LslInletOptions? inlet,
    LslOutletOptions? outlet,
    LslNetworkOptions? network,
    bool? replayLoop,
  }) => LslOptions(
    inlet: inlet ?? this.inlet,
    outlet: outlet ?? this.outlet,
    network: network ?? this.network,
    replayLoop: replayLoop ?? this.replayLoop,
  );

  Map<String, Object?> toJson() => {
    'inlet': inlet.toJson(),
    'outlet': outlet.toJson(),
    'network': network.toJson(),
    'replay_loop': replayLoop,
  };

  factory LslOptions.fromJson(Map<String, Object?> j) {
    Map<String, Object?> sub(String k) =>
        j[k] is Map ? (j[k] as Map).cast<String, Object?>() : const {};
    return LslOptions(
      inlet: LslInletOptions.fromJson(sub('inlet')),
      outlet: LslOutletOptions.fromJson(sub('outlet')),
      network: LslNetworkOptions.fromJson(sub('network')),
      replayLoop: _bool(j['replay_loop'], false),
    );
  }
}

int _int(Object? v, int d, int lo, int hi) =>
    v is num && v >= lo && v <= hi ? v.toInt() : d;

bool _bool(Object? v, bool d) => v is bool ? v : d;
