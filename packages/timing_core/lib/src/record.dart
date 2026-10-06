import 'dart:convert';
import 'dart:typed_data';

import 'package:xdf/xdf.dart';
import 'package:xml/xml.dart';

/// What a device recorded during one run, kept in its log's file header.
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

/// The element of the XDF file header that holds the [RunHeader] as JSON.
const String _headerElement = 'transport_timing';

const String _sentStream = 'tt.sent';
const String _receivedStream = 'tt.received';
const String _clockStream = 'tt.clock';
const String _markerStream = 'tt.markers';
const String _eventStream = 'tt.events';

/// A sink that keeps what it is given in memory: a log is written here
/// during a run, so that no file I/O competes with the measurement, and
/// saved afterwards.
final class BytesSink implements Sink<List<int>> {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Writes a run log as an XDF file, so it opens in any XDF tool as well as
/// in the analysis here.
///
/// | stream | samples | time stamp |
/// |---|---|---|
/// | `tt.sent` | `seq` | this device's clock at the send |
/// | `tt.received`, one per sender (its `source_id`) | `seq, source_clock, received_clock, clock_offset, uncertainty` | the sender's clock at the send |
/// | `tt.clock`, one per sender | `offset, remote_time, uncertainty, reset` | this device's clock at the estimate |
/// | `tt.markers` | text: `kind id [source]` | this device's clock |
/// | `tt.events` | text: `name [json]` | this device's clock |
///
/// Clocks are seconds; a value that was not known is NaN. Each clock-offset
/// estimate is also written as a standard XDF clock offset of its
/// `tt.received` stream, so a reader that synchronises clocks (pyxdf's
/// `load_xdf`, this repository's `loadXdf`) maps that stream's time stamps
/// onto this device's clock, and `received_clock − time stamp` is then the
/// latency. The [RunHeader] is in the file header's `transport_timing`
/// element, as JSON.
///
/// Call [close] when the run is over.
final class RunLogWriter {
  RunLogWriter(Sink<List<int>> sink, this.header)
    : _xdf = XdfWriter(
        sink,
        header: {
          'datetime': header.startedAt.toUtc().toIso8601String(),
          _headerElement: jsonEncode(header.toJson()),
        },
      );

  final RunHeader header;
  final XdfWriter _xdf;
  int _nextId = 1;
  _Buffer? _sent;
  final Map<String, _Buffer> _received = {};
  final Map<String, _Buffer> _clock = {};
  int? _markers;
  int? _events;

  _Buffer _numeric(
    String name, {
    required List<XdfChannel> channels,
    double rate = 0,
    String sourceId = '',
  }) {
    final id = _nextId++;
    _xdf.addStream(
      id,
      XdfStreamInfo(
        name: name,
        type: 'Timing',
        channelCount: channels.length,
        nominalRate: rate,
        format: XdfFormat.double64,
        sourceId: sourceId,
        hostname: header.deviceName,
        channels: channels,
      ),
    );
    return _Buffer(_xdf, id);
  }

  int _text(String name) {
    final id = _nextId++;
    _xdf.addStream(
      id,
      XdfStreamInfo(
        name: name,
        type: 'Markers',
        channelCount: 1,
        format: XdfFormat.string,
        hostname: header.deviceName,
      ),
    );
    return id;
  }

  /// This device sent sample [seq] at [sendClock].
  void sent(int seq, double sendClock) {
    final buffer = _sent ??= _numeric(
      _sentStream,
      rate: header.sampleRate,
      sourceId: header.sourceId ?? '',
      channels: const [XdfChannel(label: 'seq')],
    );
    buffer.add(sendClock, [seq.toDouble()]);
  }

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
  }) {
    final buffer = _received[sourceId] ??= _numeric(
      _receivedStream,
      rate: header.sampleRate,
      sourceId: sourceId,
      channels: const [
        XdfChannel(label: 'seq'),
        XdfChannel(label: 'source_clock', unit: 'seconds'),
        XdfChannel(label: 'received_clock', unit: 'seconds'),
        XdfChannel(label: 'clock_offset', unit: 'seconds'),
        XdfChannel(label: 'uncertainty', unit: 'seconds'),
      ],
    );
    // XDF has no "unknown" time stamp, so a sample whose sender's clock is
    // not known is placed by its arrival; the source_clock channel still
    // says which it was.
    buffer.add(sourceClock ?? receivedClock, [
      seq.toDouble(),
      sourceClock ?? double.nan,
      receivedClock,
      clockOffset ?? double.nan,
      uncertainty ?? double.nan,
    ]);
  }

  /// A clock-offset estimate for [sourceId], taken at [receivedClock].
  void clockSync(
    String sourceId, {
    required double receivedClock,
    double? offset,
    double? remoteTime,
    double? uncertainty,
    bool clockReset = false,
  }) {
    final buffer = _clock[sourceId] ??= _numeric(
      _clockStream,
      sourceId: sourceId,
      channels: const [
        XdfChannel(label: 'offset', unit: 'seconds'),
        XdfChannel(label: 'remote_time', unit: 'seconds'),
        XdfChannel(label: 'uncertainty', unit: 'seconds'),
        XdfChannel(label: 'reset'),
      ],
    );
    buffer.add(receivedClock, [
      offset ?? double.nan,
      remoteTime ?? double.nan,
      uncertainty ?? double.nan,
      clockReset ? 1 : 0,
    ]);
    final received = _received[sourceId];
    if (offset != null && received != null) {
      _xdf.writeClockOffset(received.id, receivedClock, offset);
    } else if (offset != null) {
      // Before the source's first sample: its stream does not exist yet.
      (_earlyOffsets[sourceId] ??= []).add((receivedClock, offset));
    }
  }

  /// Offsets estimated before a source's first sample, written with it.
  final Map<String, List<(double, double)>> _earlyOffsets = {};

  /// A local moment tied to sample [id], e.g. `touch` or `shown`;
  /// [sourceId] is whose sample it was, when it was not this device's.
  void marker(String kind, int id, double clock, {String? sourceId}) =>
      _xdf.writeStrings(
        _markers ??= _text(_markerStream),
        [clock],
        [sourceId == null ? '$kind $id' : '$kind $id $sourceId'],
      );

  /// Something that happened during the run (started, stopped, a peer left).
  void event(double clock, String name, [Map<String, dynamic>? detail]) =>
      _xdf.writeStrings(
        _events ??= _text(_eventStream),
        [clock],
        [detail == null ? name : '$name ${jsonEncode(detail)}'],
      );

  /// Writes what is still buffered and the stream footers, and closes the
  /// sink.
  Future<void> close() async {
    _sent?.flush();
    for (final entry in _received.entries) {
      entry.value.flush();
      for (final (time, offset)
          in _earlyOffsets[entry.key] ?? const <(double, double)>[]) {
        _xdf.writeClockOffset(entry.value.id, time, offset);
      }
    }
    for (final buffer in _clock.values) {
      buffer.flush();
    }
    await _xdf.close();
  }
}

/// The samples of one stream not yet written, so they go out as chunks of
/// many rather than one chunk each.
final class _Buffer {
  _Buffer(this._xdf, this.id);

  static const int _chunk = 512;

  final XdfWriter _xdf;
  final int id;
  final List<double> _timestamps = [];
  final List<double> _values = [];

  void add(double timestamp, List<double> values) {
    _timestamps.add(timestamp);
    _values.addAll(values);
    if (_timestamps.length >= _chunk) flush();
  }

  void flush() {
    if (_timestamps.isEmpty) return;
    _xdf.writeSamples(id, _timestamps, _values);
    _timestamps.clear();
    _values.clear();
  }
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

  /// Reads a log written by [RunLogWriter].
  ///
  /// Throws [FormatException] if [bytes] are not a run log (another XDF
  /// file, or not XDF at all).
  factory RunLog.parse(Uint8List bytes) {
    final XdfRecording recording;
    try {
      // As recorded: the analysis applies the offsets itself, sample by
      // sample, and must not have them or the jitter smoothed away first.
      recording = loadXdf(
        bytes,
        options: const XdfSyncOptions(
          synchronizeClocks: false,
          handleClockResets: false,
          dejitterTimestamps: false,
        ),
      );
    } catch (_) {
      throw const FormatException('Not a transport_timing run log');
    }
    final headerText = recording.header?.getElement(_headerElement)?.innerText;
    if (headerText == null) {
      throw const FormatException('Not a transport_timing run log');
    }
    final Object? json;
    try {
      json = jsonDecode(headerText);
    } on FormatException {
      throw const FormatException('Not a transport_timing run log');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Not a transport_timing run log');
    }
    final header = RunHeader.fromJson(json);

    Int32List ints(Float64List values) =>
        Int32List.fromList([for (final v in values) v.toInt()]);

    var sent = SentSeries(Int32List(0), Float64List(0));
    final received = <String, ReceivedSeries>{};
    final syncs = <String, SyncSeries>{};
    final markers = <Marker>[];
    final events = <LogEvent>[];
    try {
      for (final stream in recording.streams) {
        final c = stream.channels;
        switch (stream.info.name) {
          case _sentStream:
            sent = SentSeries(ints(c[0]), stream.timestamps);
          case _receivedStream:
            received[stream.info.sourceId] = ReceivedSeries(
              ints(c[0]),
              c[1],
              c[2],
              c[3],
              c[4],
            );
          case _clockStream:
            syncs[stream.info.sourceId] = SyncSeries(
              c[0],
              c[1],
              c[2],
              stream.timestamps,
              [for (final v in c[3]) v != 0],
            );
          case _markerStream:
            for (var i = 0; i < stream.length; i++) {
              final parts = stream.strings[i][0].split(' ');
              markers.add(
                Marker(
                  parts[0],
                  int.parse(parts[1]),
                  stream.timestamps[i],
                  parts.length > 2 ? parts.sublist(2).join(' ') : null,
                ),
              );
            }
          case _eventStream:
            for (var i = 0; i < stream.length; i++) {
              final text = stream.strings[i][0];
              final space = text.indexOf(' ');
              events.add(
                LogEvent(
                  stream.timestamps[i],
                  space < 0 ? text : text.substring(0, space),
                  space < 0
                      ? null
                      : jsonDecode(text.substring(space + 1))
                            as Map<String, dynamic>,
                ),
              );
            }
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      // A stream with too few channels or a mistyped value (RangeError,
      // TypeError) is a bad file, not a bug in the caller.
      throw const FormatException('Malformed transport_timing run log');
    }
    return RunLog(
      header: header,
      sent: sent,
      received: received,
      syncs: syncs,
      markers: markers,
      events: events,
    );
  }
}
