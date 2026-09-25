import 'package:signal_core/signal_core.dart';

import 'xdf_file.dart';
import 'xdf_source.dart';

/// No isolates here (the web).
const bool isolatesSupported = false;

Future<XdfRecordingSource> openInIsolate(
  ByteSourceSpec spec,
  XdfFileOptions options,
) => throw UnsupportedError('Isolates are not supported here');
