import 'dart:convert';
import 'dart:typed_data';

/// What a line of text was.
sealed class SerialLine {}

/// Channel names (a header line, or the names of `name:value` pairs).
class SerialLabels extends SerialLine {
  final List<String> labels;
  SerialLabels(this.labels);
}

/// One sample's values.
class SerialValues extends SerialLine {
  final Float64List values;
  SerialValues(this.values);
}

/// Splits bytes from a serial port into lines of numbers, as devices like
/// an Arduino print them: separated by commas, semicolons, tabs or spaces
/// (`1.5, 2, -3`), or as `name:value` pairs (the Arduino Serial Plotter's
/// format, `x:1.5 y:2`). A line of names only is a header.
class SerialLineParser {
  final _pending = <int>[];
  static final _split = RegExp(r'[,;\t ]+');

  /// Lines completed by [bytes].
  List<SerialLine> add(List<int> bytes) {
    final out = <SerialLine>[];
    for (final b in bytes) {
      if (b == 0x0A) {
        final line = parse(utf8.decode(_pending, allowMalformed: true));
        if (line != null) out.add(line);
        _pending.clear();
      } else if (b != 0x0D) {
        _pending.add(b);
        // A device that never ends a line: drop what piles up.
        if (_pending.length > 65536) _pending.clear();
      }
    }
    return out;
  }

  /// Parse one line, or null if it is neither numbers nor names.
  static SerialLine? parse(String text) {
    final tokens = [
      for (final t in text.trim().split(_split))
        if (t.isNotEmpty) t,
    ];
    if (tokens.isEmpty) return null;
    if (tokens.every((t) => t.contains(':'))) {
      final labels = <String>[];
      final values = Float64List(tokens.length);
      for (var i = 0; i < tokens.length; i++) {
        final at = tokens[i].lastIndexOf(':');
        labels.add(tokens[i].substring(0, at));
        final v = double.tryParse(tokens[i].substring(at + 1));
        if (v == null) return null;
        values[i] = v;
      }
      return _Pairs(labels, values);
    }
    final values = [for (final t in tokens) double.tryParse(t)];
    if (values.every((v) => v != null)) {
      return SerialValues(Float64List.fromList(values.cast<double>()));
    }
    if (values.every((v) => v == null)) return SerialLabels(tokens);
    return null; // mixed: e.g. a debug message
  }
}

/// `name:value` pairs: labels and values in one line.
class _Pairs extends SerialValues implements SerialLabels {
  @override
  final List<String> labels;
  _Pairs(this.labels, Float64List values) : super(values);
}
