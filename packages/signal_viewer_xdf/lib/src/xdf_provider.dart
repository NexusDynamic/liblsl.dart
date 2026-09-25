import 'package:signal_viewer/signal_viewer.dart';

import 'xdf_session.dart';

/// Opens .xdf recordings (e.g. from LabRecorder), a tab per stream.
class XdfProvider extends SourceProvider {
  @override
  List<String> get fileExtensions => const ['xdf'];

  @override
  Future<SourceSession> openFile(PickedFile file) => XdfSession.open(
    file.name,
    file.spec,
    path: file.path,
    cacheBytes: app.prefs.cacheMb << 20,
  );
}
