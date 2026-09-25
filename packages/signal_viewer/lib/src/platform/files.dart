import 'package:flutter/widgets.dart';
import 'package:signal_core/signal_core.dart';

import 'files_stub.dart'
    if (dart.library.io) 'files_io.dart'
    if (dart.library.js_interop) 'files_web.dart'
    as platform;

/// A file chosen by the user: its name, and how to read its bytes.
class PickedFile {
  final String name;
  final ByteSourceSpec spec;

  /// Path on disk, where there is one (for recent files).
  final String? path;

  const PickedFile(this.name, this.spec, {this.path});
}

/// Ask the user for files with [extensions] (lower case, without dots).
Future<List<PickedFile>> pickFiles(
  List<String> extensions, {
  String? initialDirectory,
}) => platform.pickFiles(extensions, initialDirectory: initialDirectory);

/// A recording on disk by path, if it (still) exists. Native only.
PickedFile? fileAtPath(String path) => platform.fileAtPath(path);

/// Whether files can be opened by path (for recent files).
bool get supportsPaths => platform.supportsPaths;

/// Wraps [child] so files can be dropped on it.
Widget fileDropTarget({
  required Widget child,
  required void Function(List<PickedFile> files) onDrop,
  required void Function(bool hovering, bool acceptable) onHover,
}) => platform.fileDropTarget(child: child, onDrop: onDrop, onHover: onHover);

/// A sink to record a live session to, chosen by the user, and a
/// description of where it goes. Null if cancelled.
Future<(Sink<List<int>>, String)?> recordingSink(
  String suggestedName, {
  String? directory,
}) => platform.recordingSink(suggestedName, directory: directory);
