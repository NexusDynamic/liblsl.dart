import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import 'format.dart';
import 'stream_info.dart';

class _Written {
  final XdfStreamInfo info;
  double? first;
  double? last;
  int count = 0;
  final List<XdfClockOffset> offsets = [];
  _Written(this.info);
}

/// Writes an XDF file to [sink] as data comes in, like LabRecorder: the
/// file header first, then stream headers, samples, clock offsets and
/// boundaries in any order, and each stream's footer on [close].
///
/// ```dart
/// final w = XdfWriter(File('out.xdf').openWrite());
/// w.addStream(1, XdfStreamInfo(name: 'EEG', channelCount: 8,
///     nominalRate: 500, type: 'EEG'));
/// w.writeSamples(1, timestamps, values); // values sample after sample
/// await w.close();
/// ```
class XdfWriter {
  final Sink<List<int>> sink;
  final Map<int, _Written> _streams = {};
  bool _closed = false;

  /// Starts the file with a file header holding [header] (e.g.
  /// `{'datetime': ...}`) besides the XDF version.
  XdfWriter(this.sink, {Map<String, String> header = const {}}) {
    sink.add(xdfMagic);
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0"');
    b.element(
      'info',
      nest: () {
        b.element('version', nest: '1.0');
        for (final e in header.entries) {
          b.element(e.key, nest: e.value);
        }
      },
    );
    _chunk(XdfTag.fileHeader, utf8.encode(b.buildDocument().toXmlString()));
  }

  void _chunk(XdfTag tag, List<int> content, [int? streamId]) {
    if (_closed) throw StateError('Writer is closed');
    final w = XdfBytesWriter();
    final length = 2 + (streamId == null ? 0 : 4) + content.length;
    w.varLen(length);
    w.uint16(tag.value);
    if (streamId != null) w.uint32(streamId);
    w.bytes(content);
    sink.add(w.takeBytes());
  }

  _Written _stream(int id) =>
      _streams[id] ?? (throw ArgumentError('Stream $id was not added'));

  /// Write the header of stream [id].
  void addStream(int id, XdfStreamInfo info) {
    if (_streams.containsKey(id)) {
      throw ArgumentError('Stream $id was already added');
    }
    _streams[id] = _Written(info);
    _chunk(XdfTag.streamHeader, utf8.encode(info.toXmlString()), id);
  }

  void _track(_Written s, List<double> timestamps) {
    for (final t in timestamps) {
      if (t.isNaN) continue;
      s.first ??= t;
      s.last = t;
    }
    s.count += timestamps.length;
  }

  /// Write samples of numeric stream [id]: [values] holds them sample after
  /// sample (`[sample * channels + channel]`). A NaN time stamp is left
  /// out (readers take the previous one plus 1 / nominal rate).
  void writeSamples(int id, List<double> timestamps, List<double> values) {
    final s = _stream(id);
    final ch = s.info.channelCount;
    if (s.info.format.isString) {
      throw ArgumentError('Stream $id holds strings; use writeStrings');
    }
    if (values.length != timestamps.length * ch) {
      throw ArgumentError(
        'Expected ${timestamps.length * ch} values, got ${values.length}',
      );
    }
    final w = XdfBytesWriter();
    w.varLen(timestamps.length);
    for (var i = 0; i < timestamps.length; i++) {
      _timestamp(w, timestamps[i]);
      w.values(s.info.format, values.sublist(i * ch, i * ch + ch));
    }
    _chunk(XdfTag.samples, w.takeBytes(), id);
    _track(s, timestamps);
  }

  /// Write samples of string stream [id]: [values] sample after sample.
  void writeStrings(int id, List<double> timestamps, List<String> values) {
    final s = _stream(id);
    final ch = s.info.channelCount;
    if (!s.info.format.isString) {
      throw ArgumentError('Stream $id is numeric; use writeSamples');
    }
    if (values.length != timestamps.length * ch) {
      throw ArgumentError(
        'Expected ${timestamps.length * ch} values, got ${values.length}',
      );
    }
    final w = XdfBytesWriter();
    w.varLen(timestamps.length);
    for (var i = 0; i < timestamps.length; i++) {
      _timestamp(w, timestamps[i]);
      for (var c = 0; c < ch; c++) {
        w.string(values[i * ch + c]);
      }
    }
    _chunk(XdfTag.samples, w.takeBytes(), id);
    _track(s, timestamps);
  }

  static void _timestamp(XdfBytesWriter w, double t) {
    if (t.isNaN) {
      w.uint8(0);
    } else {
      w.uint8(8);
      w.float64(t);
    }
  }

  /// Write a clock offset of stream [id], see [XdfClockOffset].
  void writeClockOffset(int id, double time, double value) {
    final s = _stream(id);
    final w = XdfBytesWriter()
      ..float64(time)
      ..float64(value);
    _chunk(XdfTag.clockOffset, w.takeBytes(), id);
    s.offsets.add(XdfClockOffset(time, value));
  }

  /// Write a boundary chunk, which lets readers recover from damage before
  /// it.
  void writeBoundary() => _chunk(XdfTag.boundary, xdfBoundaryUuid);

  /// Write the footers of all streams and close [sink].
  Future<void> close() async {
    if (_closed) return;
    for (final e in _streams.entries) {
      final s = e.value;
      final xml = XdfStreamFooter.build(
        firstTimestamp: s.first ?? 0,
        lastTimestamp: s.last ?? 0,
        sampleCount: s.count,
        clockOffsets: s.offsets,
      );
      _chunk(XdfTag.streamFooter, utf8.encode(xml), e.key);
    }
    _closed = true;
    final sink = this.sink;
    if (sink is StreamSink<List<int>>) {
      await sink.close();
    } else {
      sink.close();
    }
  }
}
