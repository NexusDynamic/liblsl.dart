import 'dart:convert';
import 'dart:typed_data';

/// What a device recorded during one run, as the first line of its log.
///
/// A run is one test executed by every device in a session; each device
/// writes one log, and logs with the same [runId] are analysed together.
final class RunHeader {
  static const String format = 'transport_timing';
  static const int version = 1;

  /// Shared by every device's log of the same run.
  final String runId;

  /// Wall-clock start, for people; no measurement uses it.
  final DateTime startedAt;

  final String deviceId;
  final String deviceName;

  /// How other devices identify the stream this device sends: the id their
  /// `R` rows name it by (LSL's `source_id`, a peer's node uId). Null if
  /// this device sends nothing.
  final String? sourceId;

  /// `latency` or `interactive`.
  final String test;

  /// `lsl`, `lsl-coordinator`, `websocket`, `webrtc` or `memory`.
  final String backend;

  /// Nominal send rate in Hz; 0 for an irregular stream.
  final double sampleRate;
  final int channels;
  final String dataType;

  /// How samples are received, e.g. `polled`, `busy-wait` or `event`.
  final String? receiveMode;

  /// Seconds between polls when [receiveMode] polls; bounds what the
  /// receive side adds to every latency.
  final double? pollInterval;

  /// How samples are sent, e.g. `async`, `sync` or `sync-blocking`.
  final String? sendMode;

  /// Anything else worth comparing runs by (platform, versions, options).
  final Map<String, dynamic> extra;

  const RunHeader({
    required this.runId,
    required this.startedAt,
    required this.deviceId,
    required this.deviceName,
    required this.test,
    required this.backend,
    required this.sampleRate,
    this.sourceId,
    this.channels = 1,
    this.dataType = 'double64',
    this.receiveMode,
    this.pollInterval,
    this.sendMode,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'runId': runId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'deviceName': deviceName,
    'sourceId': sourceId,
    'test': test,
    'backend': backend,
    'sampleRate': sampleRate,
    'channels': channels,
    'dataType': dataType,
    'receiveMode': receiveMode,
    'pollInterval': pollInterval,
    'sendMode': sendMode,
    'extra': extra,
  };

  /// Throws [FormatException] if [json] is not a header this version reads.
  factory RunHeader.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const FormatException('Not a transport_timing run log');
    }
    if (json['version'] != version) {
      throw FormatException('Unsupported run log version ${json['version']}');
    }
    return RunHeader(
      runId: json['runId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      sourceId: json['sourceId'] as String?,
      test: json['test'] as String,
      backend: json['backend'] as String,
      sampleRate: (json['sampleRate'] as num).toDouble(),
      channels: json['channels'] as int? ?? 1,
      dataType: json['dataType'] as String? ?? 'double64',
      receiveMode: json['receiveMode'] as String?,
      pollInterval: (json['pollInterval'] as num?)?.toDouble(),
      sendMode: json['sendMode'] as String?,
      extra: (json['extra'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Writes a run log: the header as one line of JSON, then one row per line.
///
/// | row | fields |
/// |---|---|
/// | `D` | index, source id — names a source for the rows that follow |
/// | `S` | seq, sendClock |
/// | `R` | source, seq, sourceClock, receivedClock, clockOffset, uncertainty |
/// | `C` | source, offset, remoteTime, uncertainty, receivedClock, reset |
/// | `M` | kind, id, clock, source |
/// | `E` | clock, name, detail (JSON) |
///
/// Clocks are seconds on the recording device's monotonic clock, except
/// `sourceClock` and `remoteTime`, which are the sender's. An empty field is
/// a value that was not known.
///
/// [sink] can be a `StringBuffer` (keep the log in memory and write it after
/// the run, so no file I/O competes with the measurement) or an `IOSink`.
final class RunLogWriter {
  final StringSink sink;
  final Map<String, int> _sources = {};

  RunLogWriter(this.sink, RunHeader header) {
    sink.writeln(jsonEncode(header.toJson()));
  }

  int _source(String sourceId) => _sources.putIfAbsent(sourceId, () {
    final index = _sources.length;
    sink.writeln('D,$index,${_oneLine(sourceId)}');
    return index;
  });

  /// This device sent sample [seq] at [sendClock].
  void sent(int seq, double sendClock) => sink.writeln('S,$seq,$sendClock');

  /// This device received sample [seq] from [sourceId].
  ///
  /// [sourceClock] is the sender's clock when it sent, [clockOffset] what to
  /// add to map that into this device's clock, and [uncertainty] the full
  /// round trip of the probe behind the offset (the offset is within half
  /// of it).
  void received(
    String sourceId,
    int seq, {
    required double receivedClock,
    double? sourceClock,
    double? clockOffset,
    double? uncertainty,
  }) => sink.writeln(
    'R,${_source(sourceId)},$seq,${_f(sourceClock)},$receivedClock,'
    '${_f(clockOffset)},${_f(uncertainty)}',
  );

  /// A clock-offset estimate for [sourceId], taken at [receivedClock].
  void clockSync(
    String sourceId, {
    required double receivedClock,
    double? offset,
    double? remoteTime,
    double? uncertainty,
    bool clockReset = false,
  }) => sink.writeln(
    'C,${_source(sourceId)},${_f(offset)},${_f(remoteTime)},'
    '${_f(uncertainty)},$receivedClock,${clockReset ? 1 : 0}',
  );

  /// A local moment tied to sample [id], e.g. `touch` or `shown`;
  /// [sourceId] is whose sample it was, when it was not this device's.
  void marker(String kind, int id, double clock, {String? sourceId}) =>
      sink.writeln(
        'M,$kind,$id,$clock,${sourceId == null ? '' : _source(sourceId)}',
      );

  /// Something that happened during the run (started, stopped, a peer left).
  void event(double clock, String name, [Map<String, dynamic>? detail]) => sink
      .writeln('E,$clock,$name,${detail == null ? '' : jsonEncode(detail)}');

  static String _f(double? value) =>
      value == null || value.isNaN ? '' : value.toString();

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n]'), ' ');
}

/// Samples this device sent, in the order it sent them.
final class SentSeries {
  final Int32List seq;
  final Float64List sendClock;
  const SentSeries(this.seq, this.sendClock);
  int get length => seq.length;
}

/// Samples received from one source, in arrival order. NaN is a value that
/// was not known.
final class ReceivedSeries {
  final Int32List seq;
  final Float64List sourceClock;
  final Float64List receivedClock;
  final Float64List clockOffset;
  final Float64List uncertainty;
  const ReceivedSeries(
    this.seq,
    this.sourceClock,
    this.receivedClock,
    this.clockOffset,
    this.uncertainty,
  );
  int get length => seq.length;
}

/// Clock-offset estimates for one source, in the order they were taken.
final class SyncSeries {
  final Float64List offset;
  final Float64List remoteTime;
  final Float64List uncertainty;
  final Float64List receivedClock;
  final List<bool> clockReset;
  const SyncSeries(
    this.offset,
    this.remoteTime,
    this.uncertainty,
    this.receivedClock,
    this.clockReset,
  );
  int get length => offset.length;
}

final class Marker {
  final String kind;
  final int id;
  final double clock;
  final String? sourceId;
  const Marker(this.kind, this.id, this.clock, this.sourceId);
}

final class LogEvent {
  final double clock;
  final String name;
  final Map<String, dynamic>? detail;
  const LogEvent(this.clock, this.name, this.detail);
}

/// One device's log of one run, read back into columns.
final class RunLog {
  final RunHeader header;
  final SentSeries sent;

  /// By source id.
  final Map<String, ReceivedSeries> received;

  /// By source id.
  final Map<String, SyncSeries> syncs;
  final List<Marker> markers;
  final List<LogEvent> events;

  const RunLog({
    required this.header,
    required this.sent,
    required this.received,
    required this.syncs,
    required this.markers,
    required this.events,
  });

  /// Throws [FormatException] if [lines] are not a run log.
  factory RunLog.parse(Iterable<String> lines) {
    final builder = RunLogBuilder();
    lines.forEach(builder.addLine);
    return builder.build();
  }

  /// Throws [FormatException] if [lines] are not a run log.
  static Future<RunLog> fromStream(Stream<String> lines) async {
    final builder = RunLogBuilder();
    await lines.forEach(builder.addLine);
    return builder.build();
  }
}

/// Reads a run log line by line.
final class RunLogBuilder {
  RunHeader? _header;
  int _line = 0;
  final List<String> _sourceIds = [];
  final _sentSeq = _Ints();
  final _sentClock = _Doubles();
  final Map<String, _Received> _received = {};
  final Map<String, _Syncs> _syncs = {};
  final List<Marker> _markers = [];
  final List<LogEvent> _events = [];

  void addLine(String line) {
    _line++;
    if (line.isEmpty) return;
    if (_header == null) {
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        throw const FormatException('Not a transport_timing run log');
      }
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Not a transport_timing run log');
      }
      _header = RunHeader.fromJson(json);
      return;
    }
    try {
      _addRow(line);
    } on FormatException {
      rethrow;
    } catch (_) {
      // A short or mistyped row (RangeError, TypeError) is a bad file, not
      // a bug in the caller.
      throw FormatException('Malformed row at line $_line', line);
    }
  }

  void _addRow(String line) {
    switch (line[0]) {
      case 'S':
        final f = line.split(',');
        _sentSeq.add(int.parse(f[1]));
        _sentClock.add(double.parse(f[2]));
      case 'R':
        final f = line.split(',');
        final r = _received.putIfAbsent(_sourceId(f[1]), _Received.new);
        r.seq.add(int.parse(f[2]));
        r.sourceClock.add(_d(f[3]));
        r.receivedClock.add(double.parse(f[4]));
        r.clockOffset.add(_d(f[5]));
        r.uncertainty.add(_d(f[6]));
      case 'C':
        final f = line.split(',');
        final c = _syncs.putIfAbsent(_sourceId(f[1]), _Syncs.new);
        c.offset.add(_d(f[2]));
        c.remoteTime.add(_d(f[3]));
        c.uncertainty.add(_d(f[4]));
        c.receivedClock.add(double.parse(f[5]));
        c.clockReset.add(f[6] == '1');
      case 'D':
        final comma = line.indexOf(',', 2);
        if (int.parse(line.substring(2, comma)) != _sourceIds.length) {
          throw FormatException('Source index out of order at line $_line');
        }
        _sourceIds.add(line.substring(comma + 1));
      case 'M':
        final f = line.split(',');
        _markers.add(
          Marker(
            f[1],
            int.parse(f[2]),
            double.parse(f[3]),
            f.length > 4 && f[4].isNotEmpty ? _sourceId(f[4]) : null,
          ),
        );
      case 'E':
        final afterClock = line.indexOf(',', 2);
        final afterName = line.indexOf(',', afterClock + 1);
        final detail = line.substring(afterName + 1);
        _events.add(
          LogEvent(
            double.parse(line.substring(2, afterClock)),
            line.substring(afterClock + 1, afterName),
            detail.isEmpty ? null : jsonDecode(detail) as Map<String, dynamic>,
          ),
        );
      default:
        throw FormatException('Unknown row type at line $_line', line);
    }
  }

  String _sourceId(String index) => _sourceIds[int.parse(index)];

  static double _d(String field) =>
      field.isEmpty ? double.nan : double.parse(field);

  RunLog build() {
    final header = _header;
    if (header == null) throw const FormatException('Empty run log');
    return RunLog(
      header: header,
      sent: SentSeries(_sentSeq.take(), _sentClock.take()),
      received: {
        for (final e in _received.entries)
          e.key: ReceivedSeries(
            e.value.seq.take(),
            e.value.sourceClock.take(),
            e.value.receivedClock.take(),
            e.value.clockOffset.take(),
            e.value.uncertainty.take(),
          ),
      },
      syncs: {
        for (final e in _syncs.entries)
          e.key: SyncSeries(
            e.value.offset.take(),
            e.value.remoteTime.take(),
            e.value.uncertainty.take(),
            e.value.receivedClock.take(),
            e.value.clockReset,
          ),
      },
      markers: _markers,
      events: _events,
    );
  }
}

final class _Received {
  final seq = _Ints();
  final sourceClock = _Doubles();
  final receivedClock = _Doubles();
  final clockOffset = _Doubles();
  final uncertainty = _Doubles();
}

final class _Syncs {
  final offset = _Doubles();
  final remoteTime = _Doubles();
  final uncertainty = _Doubles();
  final receivedClock = _Doubles();
  final clockReset = <bool>[];
}

final class _Doubles {
  Float64List _values = Float64List(1024);
  int _length = 0;

  void add(double value) {
    if (_length == _values.length) {
      _values = Float64List(_length * 2)..setRange(0, _length, _values);
    }
    _values[_length++] = value;
  }

  Float64List take() => Float64List.sublistView(_values, 0, _length);
}

final class _Ints {
  Int32List _values = Int32List(1024);
  int _length = 0;

  void add(int value) {
    if (_length == _values.length) {
      _values = Int32List(_length * 2)..setRange(0, _length, _values);
    }
    _values[_length++] = value;
  }

  Int32List take() => Int32List.sublistView(_values, 0, _length);
}
