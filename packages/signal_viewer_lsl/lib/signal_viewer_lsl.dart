/// Lab Streaming Layer for `signal_viewer`: an [LslProvider] that finds
/// streams on the network and shows them in tabs, records, replays,
/// forwards and bridges them. The LSL facade ([lsl]), recorder and bridge
/// are `package:lsl_tools`, re-exported here.
///
/// On the web, [LslBackend.supported] is false and nothing loads liblsl.
library;

export 'package:lsl_tools/lsl_tools.dart';

export 'src/lsl_dialogs.dart';
export 'src/lsl_forward.dart';
export 'src/lsl_provider.dart';
export 'src/lsl_replay.dart';
export 'src/lsl_session.dart';
