/// Lab Streaming Layer for `signal_viewer`: an [LslProvider] that finds
/// streams on the network and shows them in tabs, and a web-safe facade
/// ([lsl]) over `package:liblsl` for inlets and outlets.
///
/// On the web, [LslBackend.supported] is false and nothing loads liblsl.
library;

export 'src/lsl.dart';
export 'src/lsl_dialogs.dart';
export 'src/lsl_provider.dart';
export 'src/lsl_session.dart';
