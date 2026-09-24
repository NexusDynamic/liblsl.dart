import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'chunks.dart';
import 'format.dart';
import 'stream_info.dart';
import 'sync.dart';

/// One stream of a loaded XDF file.
class XdfStream {
  /// The stream's id in the file.
  final int id;
  final XdfStreamInfo info;
  XdfStreamFooter? footer;

  /// Time stamps in seconds, processed as [XdfSyncOptions] say.
  Float64List timestamps;

  /// Numeric values per channel (`channels[c][sample]`); empty for string
  /// streams.
  List<Float64List> channels;

  /// String values per sample (`strings[sample][c]`); empty for numeric
  /// streams.
  List<List<String>> strings;

  final List<double> clockTimes;
  final List<double> clockValues;

  /// Samples per second measured from the time stamps (0 for irregular
  /// streams or without dejittering).
  double effectiveRate = 0;

  /// Ranges of samples between breaks (see [XdfSyncOptions]).
  List<XdfRange> segments = const [];

  /// Ranges of samples each clock correction applies to.
  List<XdfRange> clockSegments = const [];

  XdfStream(
    this.id,
    this.info, {
    required this.timestamps,
    required this.channels,
    required this.strings,
    required this.clockTimes,
    required this.clockValues,
  });

  int get length => timestamps.length;

  @override
  String toString() => 'XdfStream($id, ${info.name}, $length samples)';
}

/// A loaded XDF file.
class XdfRecording {
  /// The file header's `info` element, if any.
  final XmlElement? header;
  final List<XdfStream> streams;

  const XdfRecording(this.header, this.streams);

  /// The stream named [name], or null.
  XdfStream? stream(String name) =>
      streams.where((s) => s.info.name == name).firstOrNull;
}

class _Building {
  final int id;
  final XdfStreamInfo info;
  final List<Float64List> ts = [];
  final List<Float64List> values = [];
  final List<String> strings = [];
  final List<double> clockTimes = [];
  final List<double> clockValues = [];
  XdfStreamFooter? footer;
  double last = 0;
  _Building(this.id, this.info);
}

/// Whether a stream's header says it can drop samples
/// (`desc/synchronization/can_drop_samples`), e.g. video.
bool canDropSamples(XdfStreamInfo info) =>
    info.xml
        .getElement('desc')
        ?.getElement('synchronization')
        ?.getElement('can_drop_samples')
        ?.innerText
        .trim()
        .toLowerCase() ==
    'true';

/// Load a whole XDF file from [bytes], like pyxdf's `load_xdf`: clock
/// synchronisation and jitter removal as [options] say (pyxdf's defaults).
/// Samples of streams not in [streamIds] (when given) are skipped.
XdfRecording loadXdf(
  Uint8List bytes, {
  XdfSyncOptions options = const XdfSyncOptions(),
  Set<int>? streamIds,
}) {
  XmlElement? header;
  final streams = <int, _Building>{};
  for (final chunk in readChunks(bytes)) {
    final kind = chunk.kind;
    if (kind == XdfTag.fileHeader) {
      final doc = XmlDocument.parse(
        utf8.decode(chunk.content, allowMalformed: true),
      );
      header = doc.getElement('info') ?? doc.rootElement;
      continue;
    }
    if (kind == null || kind == XdfTag.boundary) continue;
    final id = chunk.streamId;
    if (streamIds != null && !streamIds.contains(id)) continue;
    final body = Uint8List.sublistView(chunk.content, 4);
    switch (kind) {
      case XdfTag.streamHeader:
        streams[id] = _Building(
          id,
          XdfStreamInfo.parse(utf8.decode(body, allowMalformed: true)),
        );
      case XdfTag.samples:
        final s = streams[id];
        if (s == null) continue;
        final XdfSamples samples;
        try {
          samples = readSamples(
            chunk.content,
            s.info.format,
            s.info.channelCount,
          );
        } on FormatException {
          continue; // a damaged chunk
        }
        s.last = fillTimestamps(samples.timestamps, s.last, s.info.nominalRate);
        s.ts.add(samples.timestamps);
        if (samples.values != null) s.values.add(samples.values!);
        if (samples.strings != null) s.strings.addAll(samples.strings!);
      case XdfTag.clockOffset:
        final s = streams[id];
        if (s == null) continue;
        final d = ByteData.sublistView(body);
        s.clockTimes.add(d.getFloat64(0, Endian.little));
        s.clockValues.add(d.getFloat64(8, Endian.little));
      case XdfTag.streamFooter:
        final s = streams[id];
        if (s == null) continue;
        try {
          s.footer = XdfStreamFooter.parse(
            utf8.decode(body, allowMalformed: true),
          );
        } on XmlException {
          // A damaged footer: ignore it.
        }
      case XdfTag.fileHeader || XdfTag.boundary:
        break;
    }
  }

  final out = <XdfStream>[];
  for (final s in streams.values) {
    final n = s.ts.fold(0, (a, t) => a + t.length);
    final ts = Float64List(n);
    var p = 0;
    for (final t in s.ts) {
      ts.setAll(p, t);
      p += t.length;
    }
    final ch = s.info.channelCount;
    final channels = s.info.format.isString
        ? <Float64List>[]
        : [for (var c = 0; c < ch; c++) Float64List(n)];
    if (!s.info.format.isString) {
      var row = 0;
      for (final v in s.values) {
        final rows = v.length ~/ math.max(1, ch);
        for (var i = 0; i < rows; i++, row++) {
          for (var c = 0; c < ch; c++) {
            channels[c][row] = v[i * ch + c];
          }
        }
      }
    }
    final strings = s.info.format.isString
        ? [
            for (var i = 0; i < n; i++)
              s.strings.sublist(
                i * ch,
                math.min(s.strings.length, i * ch + ch),
              ),
          ]
        : <List<String>>[];
    out.add(
      XdfStream(
        s.id,
        s.info,
        timestamps: ts,
        channels: channels,
        strings: strings,
        clockTimes: List.of(s.clockTimes),
        clockValues: List.of(s.clockValues),
      )..footer = s.footer,
    );
  }

  for (final s in out) {
    if (options.synchronizeClocks) {
      _truncateCorruptedOffsets(s);
      s.clockSegments = synchronizeClock(
        s.timestamps,
        s.clockTimes,
        s.clockValues,
        options,
      );
    }
    if (options.dejitterTimestamps) {
      final r = removeJitter(
        s.timestamps,
        s.info.nominalRate,
        options,
        canDropSamples: canDropSamples(s.info),
      );
      s.segments = r.segments;
      s.effectiveRate = r.effectiveRate;
    } else {
      final n = s.length;
      if (s.info.nominalRate != 0 && n > 1) {
        final d = s.timestamps[n - 1] - s.timestamps[0];
        s.effectiveRate = (n - 1) / d;
      }
      s.segments = n > 0 ? [(0, n - 1)] : const [];
    }
  }
  return XdfRecording(header, out);
}

/// pyxdf's fix for pylsl#67 / liblsl#246: an outlet destroyed while an
/// inlet is connected can leave an extra sample and a garbage last clock
/// offset. Both must be present to drop them.
void _truncateCorruptedOffsets(XdfStream s) {
  final count = s.footer?.sampleCount;
  if (count == null || s.length <= count || s.clockTimes.length < 3) return;
  final times = s.clockTimes, values = s.clockValues;
  final intervals = [
    for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
  ];
  double median(List<double> x) {
    final v = [...x]..sort();
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
  }

  final medianInterval = median(intervals.sublist(0, intervals.length - 1));
  final lastInterval = intervals.last.abs();
  final timeRatio = medianInterval > 0
      ? lastInterval / medianInterval
      : (lastInterval > 0 ? double.infinity : 1.0);
  final head = values.sublist(0, values.length - 1);
  final medianValue = median(head);
  final mad = median([for (final v in head) (v - medianValue).abs()]);
  final z = mad > 2.220446049250313e-16
      ? (values.last - medianValue).abs() / (1.4826 * mad)
      : 0.0;
  if (!(timeRatio > 10 || z > 10)) return;
  s.clockTimes.removeLast();
  s.clockValues.removeLast();
  s.timestamps = Float64List.fromList(s.timestamps.sublist(0, count));
  s.channels = [
    for (final c in s.channels) Float64List.fromList(c.sublist(0, count)),
  ];
  if (s.strings.isNotEmpty) s.strings = s.strings.sublist(0, count);
}
