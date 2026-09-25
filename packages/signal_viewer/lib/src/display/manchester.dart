/// Manchester-coded trigger values on a binary trigger channel.
///
/// A word is an optional preamble `0` bit, then the data bits, where a `0`
/// is high→low and a `1` is low→high around the middle of each bit
/// period. The line idles low between words.
library;

import 'dart:math' as math;

enum BitOrder { lsb, msb }

/// Silence (in bit periods) that ends a word.
const gapPeriods = 1.5;

/// How far (in bit periods) a mid-bit edge may be from where it is expected.
const tolerance = 0.25;

class ManchesterSettings {
  final double clockHz;
  final BitOrder order;
  final bool preamble;

  const ManchesterSettings({
    this.clockHz = 18,
    this.order = BitOrder.lsb,
    this.preamble = true,
  });

  double get period => 1 / clockHz;

  @override
  bool operator ==(Object other) =>
      other is ManchesterSettings &&
      other.clockHz == clockHz &&
      other.order == order &&
      other.preamble == preamble;

  @override
  int get hashCode => Object.hash(clockHz, order, preamble);
}

class DecodedWord {
  /// Onset (start of the first bit), seconds.
  final double t;

  /// Null if the word was malformed.
  final int? value;

  /// Data bits, excluding the preamble.
  final int bits;

  const DecodedWord(this.t, this.value, this.bits);

  String get text => value?.toString() ?? '?';

  @override
  String toString() => 'DecodedWord($t, $text)';
}

/// Decode the words on one binary channel sampled at (irregular) times [t].
///
/// Rows where the level does not change are ignored, and the level before
/// the first row is taken to be idle (low). A word still within
/// [gapPeriods] of [tEnd] might not be finished and is left for later.
/// Returns the decoded words and the index of the first row not consumed.
(List<DecodedWord>, int) decodeManchester(
  List<double> t,
  List<double> level, {
  ManchesterSettings settings = const ManchesterSettings(),
  double tEnd = double.infinity,
}) {
  final rows = <int>[];
  var prev = false;
  for (var i = 0; i < t.length; i++) {
    final high = level[i] > 0.5;
    if (high != prev) rows.add(i);
    prev = high;
  }
  final edges = [for (final r in rows) t[r]];
  final rising = [for (final r in rows) level[r] > 0.5];
  final period = settings.period;
  final words = <DecodedWord>[];
  if (edges.isEmpty) return (words, t.length);
  final breaks = <int>[0];
  for (var i = 1; i < edges.length; i++) {
    if (edges[i] - edges[i - 1] > gapPeriods * period) breaks.add(i);
  }
  breaks.add(edges.length);
  for (var k = 0; k + 1 < breaks.length; k++) {
    final a = breaks[k], b = breaks[k + 1];
    if (tEnd - edges[b - 1] <= gapPeriods * period) return (words, rows[a]);
    if (!rising[a]) continue; // the tail of a word cut off at the start
    words.add(_decodeWord(edges.sublist(a, b), rising.sublist(a, b), settings));
  }
  return (words, t.length);
}

DecodedWord _decodeWord(
  List<double> edges,
  List<bool> rising,
  ManchesterSettings settings,
) {
  final period = settings.period;
  final start = edges.first;
  final bits = <int>[];
  final mids = <double>[];
  var expected = start + period / 2;
  while (true) {
    // The mid-bit edge carries the bit; re-anchor on it so clock error does
    // not accumulate.
    var best = 0;
    for (var i = 1; i < edges.length; i++) {
      if ((edges[i] - expected).abs() < (edges[best] - expected).abs()) {
        best = i;
      }
    }
    if ((edges[best] - expected).abs() > tolerance * period) break;
    bits.add(rising[best] ? 1 : 0);
    mids.add(edges[best]);
    expected = mids.last + period;
  }
  final pre = settings.preamble ? 1 : 0;
  var data = bits.length > pre ? bits.sublist(pre) : <int>[];
  final valid =
      data.isNotEmpty &&
      bits.first == 0 &&
      _edgesFit(edges, bits, mids, period);
  if (!valid) return DecodedWord(start, null, data.length);
  if (settings.order == BitOrder.msb) data = data.reversed.toList();
  var value = 0;
  for (var i = 0; i < data.length; i++) {
    value += data[i] * math.pow(2, i).toInt();
  }
  return DecodedWord(start, value, data.length);
}

/// Whether the edges are exactly those of [bits]: besides the mid-bit
/// edges, the start edge, one edge between each pair of equal bits, and a
/// final fall back to idle if the word ends high.
bool _edgesFit(
  List<double> edges,
  List<int> bits,
  List<double> mids,
  double period,
) {
  final expected = [edges.first, ...mids];
  for (var i = 0; i + 1 < mids.length; i++) {
    if (bits[i] == bits[i + 1]) expected.add((mids[i] + mids[i + 1]) / 2);
  }
  if (bits.last == 1) expected.add(mids.last + period / 2);
  if (expected.length != edges.length) return false;
  expected.sort();
  for (var i = 0; i < edges.length; i++) {
    if ((expected[i] - edges[i]).abs() > tolerance * period) return false;
  }
  return true;
}

/// Incremental decoding of a channel that arrives in chunks (live data).
class ManchesterDecoder {
  ManchesterSettings settings;
  final List<double> _t = [];
  final List<double> _level = [];

  ManchesterDecoder([this.settings = const ManchesterSettings()]);

  /// Add samples; return the words completed as of [tNow].
  List<DecodedWord> feed(List<double> t, List<double> level, double tNow) {
    _t.addAll(t);
    _level.addAll(level);
    final (words, used) = decodeManchester(
      _t,
      _level,
      settings: settings,
      tEnd: tNow,
    );
    _t.removeRange(0, used);
    _level.removeRange(0, used);
    return words;
  }
}

/// Manchester-encode [value] as ±1 samples at [rate] Hz (for tests and
/// trigger generation).
List<double> manchesterEncode(
  int value, {
  int clock = 18,
  int rate = 48000,
  BitOrder order = BitOrder.lsb,
  bool preamble = true,
}) {
  final bits = math.max(value.bitLength, 1);
  final perBit = rate ~/ clock;
  final half = perBit ~/ 2;
  final extra = preamble ? 1 : 0;
  final out = List<double>.filled(perBit * (bits + extra), 0);
  if (preamble) {
    for (var i = 0; i < perBit; i++) {
      out[i] = i < half ? 1 : -1;
    }
  }
  for (var i = 0; i < bits; i++) {
    final bit = order == BitOrder.lsb
        ? (value >> i) & 1
        : (value >> (bits - 1 - i)) & 1;
    final start = (i + extra) * perBit;
    for (var j = 0; j < perBit; j++) {
      final first = j < half;
      out[start + j] = bit == 1 ? (first ? -1 : 1) : (first ? 1 : -1);
    }
  }
  return out;
}
