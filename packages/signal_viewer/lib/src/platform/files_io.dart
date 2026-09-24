import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:signal_core/signal_core.dart';
import 'package:path_provider/path_provider.dart';

import 'files.dart';

bool get _desktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;

bool get supportsPaths => true;

String _basename(String path) => path.split(Platform.pathSeparator).last;

PickedFile? fileAtPath(String path) {
  if (!File(path).existsSync()) return null;
  return PickedFile(_basename(path), ByteSourceSpec.path(path), path: path);
}

Future<List<PickedFile>> pickFiles(
  List<String> extensions, {
  String? initialDirectory,
}) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Open recording',
    initialDirectory: initialDirectory,
    // Mobile pickers do not know most recording types.
    type: _desktop ? FileType.custom : FileType.any,
    allowedExtensions: _desktop ? extensions : null,
  );
  final out = <PickedFile>[];
  for (final f in files) {
    var path = f.path;
    if (path == null) {
      // A content URI (Android): copy it to the cache to read by offset.
      final dir = await getTemporaryDirectory();
      final copy = File('${dir.path}/${f.name}');
      final sink = copy.openWrite();
      await sink.addStream(f.readAsByteStream());
      await sink.close();
      path = copy.path;
    }
    out.add(PickedFile(f.name, ByteSourceSpec.path(path), path: path));
  }
  return out;
}

Widget fileDropTarget({
  required Widget child,
  required void Function(List<PickedFile> files) onDrop,
  required void Function(bool hovering, bool acceptable) onHover,
}) {
  if (!_desktop) return child;
  return DropTarget(
    onDragEntered: (_) => onHover(true, true),
    onDragExited: (_) => onHover(false, true),
    onDragDone: (details) {
      onHover(false, true);
      onDrop([
        for (final f in details.files)
          if (f.path.isNotEmpty)
            PickedFile(
              f.name.isNotEmpty ? f.name : _basename(f.path),
              ByteSourceSpec.path(f.path),
              path: f.path,
            ),
      ]);
    },
    child: child,
  );
}

Future<(Sink<List<int>>, String)?> recordingSink(
  String suggestedName, {
  String? directory,
}) async {
  final ext = suggestedName.split('.').last.toLowerCase();
  String path;
  if (_desktop) {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Record to',
      fileName: suggestedName,
      initialDirectory: directory,
      bytes: Uint8List(0),
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (uri == null) return null;
    path = uri.toFilePath();
    if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  } else {
    // Mobile: the app's documents folder.
    final dir = await getApplicationDocumentsDirectory();
    path = '${dir.path}/$suggestedName';
  }
  return (File(path).openWrite(), path);
}
