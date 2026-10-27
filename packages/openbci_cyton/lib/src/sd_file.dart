import 'dart:typed_data';

import 'protocol.dart';
import 'settings.dart';

/// Rate of the accelerometer readings in SD card files.
const _accelHz = 25.0;

/// Longest line: the counter, 16 channels and 3 aux values, with commas.
const _maxLine = 2 + 1 + 16 * 7 + 3 * 5 + 16;

/// One line of an SD card recording.
class CytonSdRow {
  /// The sample's place, by the counter: lost samples leave gaps.
  final int index;

  /// EEG in µV.
  final Float64List eeg;

  /// The 3 accelerometer or aux values of the line, if it has them.
  final Int32List? aux;

  const CytonSdRow(this.index, this.eeg, this.aux);
}

/// Reads an SD card recording (see [CytonSdFile]) in pieces, for files
/// too large to hold: [add] the file's bytes as they are read, and stop
/// reading once [done] (the rest of the file is unused space).
class CytonSdReader {
  /// Gain of each channel (16).
  final List<int> gains;
  final metadata = <String, String>{};

  /// 8 or 16, once the first line is read.
  int? channelCount;

  /// Samples lost (from gaps in the counter).
  int lost = 0;

  /// Lines that could not be read, such as one cut off at the end.
  int skipped = 0;

  /// Whether the unused space after the data has been reached.
  bool done = false;

  final _line = Uint8List(_maxLine);
  int _length = 0;
  bool _tooLong = false;
  String? _key;
  int _index = -1, _prev = -1, _ff = 0;

  // A line's fields: value and number of digits; 1 + 16 + 3 at most.
  final _values = Int32List(20);
  final _digits = Int32List(20);
  late final Float64List _scale = Float64List.fromList([
    for (final g in gains) cytonMicrovolts(g),
  ]);

  CytonSdReader({List<int>? gains}) : gains = gains ?? List.filled(16, 24);

  /// The lines completed by [bytes].
  List<CytonSdRow> add(List<int> bytes) {
    final rows = <CytonSdRow>[];
    for (final b in bytes) {
      if (b == 0xFF) {
        // The unused space is written with 0xFF, a block (512) or more.
        if (++_ff >= 512) {
          done = true;
          break;
        }
        continue;
      }
      _ff = 0;
      if (b == 0x0A || b == 0x0D) {
        _endLine(rows);
      } else if (b != 0) {
        if (_length < _maxLine) {
          _line[_length++] = b;
        } else {
          _tooLong = true;
        }
      }
    }
    return rows;
  }

  /// The last line, if the file does not end with a line break.
  List<CytonSdRow> close() {
    final rows = <CytonSdRow>[];
    _endLine(rows);
    return rows;
  }

  void _endLine(List<CytonSdRow> rows) {
    if (_length == 0) return;
    final row = _tooLong ? _skip() : _parse();
    _length = 0;
    _tooLong = false;
    if (row != null) rows.add(row);
  }

  CytonSdRow? _skip() {
    skipped++;
    return null;
  }

  static int _hex(int b) => switch (b) {
    >= 0x30 && <= 0x39 => b - 0x30,
    >= 0x41 && <= 0x46 => b - 0x37,
    >= 0x61 && <= 0x66 => b - 0x57,
    _ => -1,
  };

  CytonSdRow? _parse() {
    final line = _line;
    if (line[0] == 0x25) {
      // %: a metadata key, its value on the next line.
      _key = String.fromCharCodes(line, 1, _length).trim();
      metadata[_key!] = '';
      return null;
    }
    // Split at commas into hexadecimal fields.
    var fields = 0, value = 0, digits = 0;
    for (var i = 0; i <= _length; i++) {
      final b = i < _length ? line[i] : 0x2C;
      if (b == 0x2C) {
        if (fields == _values.length) return _skip();
        _values[fields] = value;
        _digits[fields] = digits;
        fields++;
        value = 0;
        digits = 0;
        continue;
      }
      final h = _hex(b);
      if (h < 0) {
        if (fields == 0 && _key != null) break; // a metadata value
        return _skip();
      }
      value = (value << 4) | h;
      digits++;
    }
    final key = _key;
    _key = null;
    if (fields <= 1) {
      if (key != null && metadata[key]!.isEmpty) {
        metadata[key] = String.fromCharCodes(line, 0, _length).trim();
      }
      return null;
    }
    channelCount ??= CytonSdFile._columns(fields);
    final n = channelCount;
    if (n == null || (fields != n + 1 && fields != n + 4)) return _skip();
    final eeg = Float64List(n);
    for (var c = 0; c < n; c++) {
      if (_digits[c + 1] != 6) return _skip();
      final v = _values[c + 1];
      eeg[c] = (v & 0x800000 != 0 ? v - 0x1000000 : v) * _scale[c];
    }
    Int32List? aux;
    if (fields == n + 4) {
      aux = Int32List(3);
      for (var i = 0; i < 3; i++) {
        aux[i] = _values[n + 1 + i];
      }
    }
    final number = _values[0];
    if (_prev < 0) {
      _index = 0;
    } else {
      final step = (number - _prev) % 256;
      _index += step == 0 ? 1 : step;
      if (step > 1) lost += step - 1;
    }
    _prev = number;
    return CytonSdRow(_index, eeg, aux);
  }
}

/// What the lines of an SD card recording hold besides the channels, and
/// its rate: decided from (the first) rows, unless given.
class CytonSdLayout {
  final double rate;

  /// Whether [rate] was estimated rather than given.
  final bool rateEstimated;

  /// Whether the lines have the accelerometer (else aux values).
  final bool hasAccel;

  /// Whether the aux values are markers.
  final bool markers;

  const CytonSdLayout(
    this.rate,
    this.rateEstimated,
    this.hasAccel,
    this.markers,
  );

  /// The accelerometer gives a reading every few lines, aux values come
  /// with every line; aux values whose last two are always 0 are markers.
  /// The rate comes from the accelerometer readings (25 Hz), or is 250 Hz.
  factory CytonSdLayout.of(
    List<CytonSdRow> rows, {
    double? rate,
    CytonBoardMode? mode,
  }) {
    var withAux = 0, firstAux = -1, lastAux = -1;
    var auxZeros = true;
    for (final r in rows) {
      final aux = r.aux;
      if (aux == null) continue;
      withAux++;
      if (firstAux < 0) firstAux = r.index;
      lastAux = r.index;
      if (aux[1] != 0 || aux[2] != 0) auxZeros = false;
    }
    final everyLine = rows.length > 1 && withAux >= 0.9 * rows.length;
    final hasAccel = switch (mode) {
      null => !everyLine,
      CytonBoardMode.defaults || CytonBoardMode.debug => true,
      _ => false,
    };
    final markers =
        mode == CytonBoardMode.marker ||
        (mode == null && everyLine && auxZeros);
    var r = rate;
    if (r == null) {
      r = 250;
      if (hasAccel && withAux >= 3) {
        final perReading = (lastAux - firstAux) / (withAux - 1);
        r = CytonSampleRate.nearest(perReading * _accelHz).hz.toDouble();
      }
    }
    return CytonSdLayout(r, rate == null, hasAccel, markers);
  }

  /// The accelerometer in g from a line's values, into [out] (3).
  static void accel(Int32List aux, Float64List out) {
    for (var i = 0; i < 3; i++) {
      final v = aux[i];
      out[i] = (v & 0x8000 != 0 ? v - 0x10000 : v) * cytonAccelScale;
    }
  }

  /// The marker in a line's aux values, or null: a byte, extended to 16
  /// bits with its sign.
  static int? marker(Int32List aux) =>
      aux[0] & 0xFF == 0 ? null : aux[0] & 0xFF;
}

/// A recording that a Cyton logged to its SD card (`OBCI_XX.TXT`): lines
/// of hexadecimal values (the sample counter, 8 or 16 channels of 24 bits,
/// and the accelerometer's 3 × 16 bits when it has a new reading), with
/// `%` lines of metadata, and the unused rest of the file's reserved space
/// filled with 0xFF.
///
/// With the accelerometer off (the marker, analog and digital board
/// modes), every line ends with the 3 aux values instead; in the marker
/// mode, the first holds the markers.
///
/// The file holds neither the sampling rate nor the gains. Unless given,
/// the rate is estimated from the accelerometer, which the board reads at
/// 25 Hz (250 Hz is assumed without it), and the gains are taken to be 24
/// (the default).
///
/// This holds the whole recording; [CytonSdReader] reads one in pieces.
class CytonSdFile {
  final int channelCount;

  /// Samples per second.
  final double rate;

  /// Whether [rate] was estimated (from the accelerometer readings).
  final bool rateEstimated;

  /// Time of each sample in seconds from the first, by the counter: lost
  /// samples leave gaps.
  final Float64List times;

  /// EEG in µV, sample after sample (`[sample * channelCount + channel]`).
  final Float64List eeg;

  /// Whether the file has the accelerometer (rather than aux values).
  final bool hasAccel;

  /// The accelerometer in g, sample after sample (3 per sample); the last
  /// reading holds until the next. Zeros without it.
  final Float64List accel;

  /// Markers (in the marker board mode): time in seconds and value.
  final List<({double time, int value})> markers;

  /// Samples lost (from gaps in the counter).
  final int lost;

  /// Lines that could not be read, such as one cut off at the end.
  final int skipped;

  /// The `%` lines, each with the line after it if that is a single value,
  /// e.g. `STOP AT` → `00006617` (the board's clock in milliseconds, in
  /// hexadecimal).
  final Map<String, String> metadata;

  CytonSdFile._(
    this.channelCount,
    this.rate,
    this.rateEstimated,
    this.times,
    this.eeg,
    this.hasAccel,
    this.accel,
    this.markers,
    this.lost,
    this.skipped,
    this.metadata,
  );

  int get length => times.length;

  /// Duration in seconds.
  double get duration => length == 0 ? 0 : times.last + 1 / rate;

  /// Whether [bytes] (e.g. the start of a file) look like a Cyton SD
  /// recording: a data line of hexadecimal values within the first lines.
  static bool looksLike(List<int> bytes) {
    final r = CytonSdReader();
    final head = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    return r.add(head).isNotEmpty;
  }

  /// Read a file's [bytes]. [rate], [gains] (16, one per channel) and
  /// [mode] are the board's settings during the recording, where known;
  /// see [CytonSdLayout.of]. [CytonSdReader] reads a file in pieces.
  static CytonSdFile parse(
    List<int> bytes, {
    double? rate,
    List<int>? gains,
    CytonBoardMode? mode,
  }) {
    final reader = CytonSdReader(gains: gains);
    final rows = reader.add(bytes)..addAll(reader.close());
    final layout = CytonSdLayout.of(rows, rate: rate, mode: mode);
    final n = reader.channelCount ?? 8;
    final t = Float64List(rows.length);
    final eeg = Float64List(rows.length * n);
    final accel = Float64List(rows.length * 3);
    final markers = <({double time, int value})>[];
    final last = Float64List(3);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      t[i] = r.index / layout.rate;
      eeg.setAll(i * n, r.eeg);
      final aux = r.aux;
      if (layout.hasAccel) {
        if (aux != null) CytonSdLayout.accel(aux, last);
        accel.setAll(i * 3, last);
      } else if (layout.markers && aux != null) {
        final m = CytonSdLayout.marker(aux);
        if (m != null) markers.add((time: t[i], value: m));
      }
    }
    return CytonSdFile._(
      n,
      layout.rate,
      layout.rateEstimated,
      t,
      eeg,
      layout.hasAccel,
      accel,
      markers,
      reader.lost,
      reader.skipped,
      reader.metadata,
    );
  }

  /// 8 or 16 channels from the number of columns, with or without the
  /// accelerometer.
  static int? _columns(int fields) => switch (fields) {
    9 || 12 => 8,
    17 || 20 => 16,
    _ => null,
  };
}
