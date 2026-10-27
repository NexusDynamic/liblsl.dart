/// Cyton SD card recordings as XDF files, for the tools that read XDF
/// (e.g. LSL Viewer, pyxdf, EEGLAB, MNE).
library;

import 'dart:typed_data';

import 'package:xdf/xdf.dart';

import 'openbci_cyton.dart';

/// What [convertCytonSdToXdf] found in a recording.
class CytonSdSummary {
  final int channelCount;
  final CytonSdLayout layout;

  /// Samples written.
  final int samples;
  final int markers;

  /// Samples lost (gaps in the counter), and lines that could not be read.
  final int lost;
  final int skipped;
  final Map<String, String> metadata;

  const CytonSdSummary(
    this.channelCount,
    this.layout,
    this.samples,
    this.markers,
    this.lost,
    this.skipped,
    this.metadata,
  );

  double get duration => samples / layout.rate;
}

/// Convert an SD card recording, read from [input] in pieces, to XDF on
/// [sink], without holding the recording: a stream of its channels (µV)
/// named [name], with [labels] and [types] (e.g. `EEG`, `EMG`) per
/// channel, one of its accelerometer (g) if it has one, and one of its
/// markers if it has any. Time stamps start at 0. Reading stops at the
/// file's unused space.
///
/// [rate], [gains] and [mode] are the board's settings, where known; the
/// first [layoutLines] lines decide the rest (see [CytonSdLayout.of]).
Future<CytonSdSummary> convertCytonSdToXdf(
  Stream<List<int>> input,
  Sink<List<int>> sink, {
  String name = 'OpenBCI Cyton',
  List<String>? labels,
  List<String>? types,
  double? rate,
  List<int>? gains,
  CytonBoardMode? mode,
  int layoutLines = 2500,
}) async {
  final reader = CytonSdReader(gains: gains);
  final pending = <CytonSdRow>[];
  _Writer? out;
  _Writer start() => _Writer(
    sink,
    CytonSdLayout.of(pending, rate: rate, mode: mode),
    reader.channelCount ?? 8,
    name,
    labels,
    types,
  );
  await for (final bytes in input) {
    pending.addAll(reader.add(bytes));
    if (out == null && pending.length >= layoutLines) out = start();
    if (out != null) {
      out.write(pending);
      pending.clear();
    }
    if (reader.done) break;
  }
  pending.addAll(reader.close());
  out ??= start();
  out.write(pending);
  await out.writer.close();
  return CytonSdSummary(
    out.channels,
    out.layout,
    out.samples,
    out.markers,
    reader.lost,
    reader.skipped,
    reader.metadata,
  );
}

class _Writer {
  final XdfWriter writer;
  final CytonSdLayout layout;
  final int channels;
  final String name;
  final Float64List _accel = Float64List(3);
  int samples = 0;
  int markers = 0;

  _Writer(
    Sink<List<int>> sink,
    this.layout,
    this.channels,
    this.name,
    List<String>? labels,
    List<String>? types,
  ) : writer = XdfWriter(sink, header: {'source': 'OpenBCI Cyton SD card'}) {
    writer.addStream(
      1,
      XdfStreamInfo(
        name: name,
        type: 'EEG',
        channelCount: channels,
        nominalRate: layout.rate,
        sourceId: 'openbci-cyton-sd',
        channels: [
          for (var c = 0; c < channels; c++)
            LSLChannel(
              labels != null && c < labels.length ? labels[c] : 'ch${c + 1}',
              unit: 'microvolts',
              type: types != null && c < types.length ? types[c] : 'EEG',
            ),
        ],
      ),
    );
    if (layout.hasAccel) {
      writer.addStream(
        2,
        XdfStreamInfo(
          name: '$name accelerometer',
          type: 'Accelerometer',
          channelCount: 3,
          nominalRate: layout.rate,
          sourceId: 'openbci-cyton-sd:accel',
          channels: const [
            LSLChannel('x', unit: 'g'),
            LSLChannel('y', unit: 'g'),
            LSLChannel('z', unit: 'g'),
          ],
        ),
      );
    }
  }

  void write(List<CytonSdRow> rows) {
    const chunk = 1000;
    for (var a = 0; a < rows.length; a += chunk) {
      final m = (rows.length - a).clamp(0, chunk);
      final times = Float64List(m);
      final eeg = Float64List(m * channels);
      final accel = layout.hasAccel ? Float64List(m * 3) : null;
      var marked = 0;
      for (var i = 0; i < m; i++) {
        final r = rows[a + i];
        times[i] = r.index / layout.rate;
        eeg.setAll(i * channels, r.eeg);
        final aux = r.aux;
        if (accel != null) {
          if (aux != null) CytonSdLayout.accel(aux, _accel);
          accel.setAll(i * 3, _accel);
        } else if (layout.markers &&
            aux != null &&
            CytonSdLayout.marker(aux) != null) {
          marked++;
        }
      }
      writer.writeSamples(1, times, eeg);
      if (accel != null) writer.writeSamples(2, times, accel);
      if (marked > 0) _markers(rows, a, m, times, marked);
      samples += m;
    }
  }

  void _markers(
    List<CytonSdRow> rows,
    int from,
    int count,
    Float64List times,
    int marked,
  ) {
    if (markers == 0) {
      writer.addStream(
        3,
        XdfStreamInfo(
          name: '$name markers',
          type: 'Markers',
          channelCount: 1,
          format: LSLChannelFormat.string,
          sourceId: 'openbci-cyton-sd:markers',
        ),
      );
    }
    final t = Float64List(marked);
    final text = List.filled(marked, '');
    var k = 0;
    for (var i = 0; i < count; i++) {
      final m = CytonSdLayout.marker(rows[from + i].aux ?? _none);
      if (m == null) continue;
      t[k] = times[i];
      text[k++] = cytonMarkerLabel(m);
    }
    writer.writeStrings(3, t, text);
    markers += marked;
  }

  static final _none = Int32List(3);
}
