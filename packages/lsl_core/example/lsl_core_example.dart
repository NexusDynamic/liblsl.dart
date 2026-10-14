import 'dart:typed_data';

import 'package:lsl_core/lsl_core.dart';

/// Values of a few channel formats written and read back, exactly.
void main() {
  final samples = <LSLChannelFormat, List<num>>{
    LSLChannelFormat.int16: [-32768, 32767],
    LSLChannelFormat.int64: [(1 << 60) + 1, -7],
    LSLChannelFormat.double64: [1 / 3, -1e-300],
  };
  for (final MapEntry(key: format, value: values) in samples.entries) {
    final bytes = ByteData(values.length * format.byteWidth);
    writeValues(bytes, 0, format, values, values.length);
    final back = readValues(bytes, 0, format, values.length);
    print('${format.name}: $back (${back.runtimeType})');
  }
}
