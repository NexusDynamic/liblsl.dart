/// Serial devices for `signal_viewer`: [SerialStreamProvider] reads lines of
/// numbers from serial ports (e.g. an Arduino) and OpenBCI Cyton boards as
/// live streams; [CytonSdProvider] opens the Cyton's SD card recordings.
library;

export 'src/cyton_dialogs.dart';
export 'src/cyton_sd_provider.dart';
export 'src/cyton_session.dart';
export 'src/line_parser.dart';
export 'src/serial_provider.dart';
export 'src/serial_session.dart';
