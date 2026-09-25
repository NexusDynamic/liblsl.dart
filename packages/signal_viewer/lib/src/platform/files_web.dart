import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:signal_core/signal_core.dart';
import 'package:web/web.dart' as web;

import 'files.dart';

bool get supportsPaths => false;

PickedFile? fileAtPath(String path) => null;

PickedFile _picked(web.File f) =>
    PickedFile(f.name, ByteSourceSpec.blob(f, name: f.name));

/// A file input, so the picked `File` is read in slices rather than loaded
/// into memory (as file_picker does on the web).
Future<List<PickedFile>> pickFiles(
  List<String> extensions, {
  String? initialDirectory,
}) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = [for (final e in extensions) '.$e'].join(',')
    ..multiple = true;
  final done = Completer<List<PickedFile>>();
  input.onchange = (web.Event _) {
    final files = input.files;
    done.complete([
      if (files != null)
        for (var i = 0; i < files.length; i++) _picked(files.item(i)!),
    ]);
  }.toJS;
  input.oncancel = (web.Event _) {
    if (!done.isCompleted) done.complete(const []);
  }.toJS;
  input.click();
  return done.future;
}

Widget fileDropTarget({
  required Widget child,
  required void Function(List<PickedFile> files) onDrop,
  required void Function(bool hovering, bool acceptable) onHover,
}) => _WebDropTarget(onDrop: onDrop, onHover: onHover, child: child);

class _WebDropTarget extends StatefulWidget {
  final Widget child;
  final void Function(List<PickedFile>) onDrop;
  final void Function(bool, bool) onHover;

  const _WebDropTarget({
    required this.child,
    required this.onDrop,
    required this.onHover,
  });

  @override
  State<_WebDropTarget> createState() => _WebDropTargetState();
}

class _WebDropTargetState extends State<_WebDropTarget> {
  late final JSFunction _over, _leave, _drop;

  @override
  void initState() {
    super.initState();
    _over = (web.DragEvent e) {
      e.preventDefault();
      widget.onHover(true, true);
    }.toJS;
    _leave = (web.DragEvent e) {
      widget.onHover(false, true);
    }.toJS;
    _drop = (web.DragEvent e) {
      e.preventDefault();
      widget.onHover(false, true);
      final files = e.dataTransfer?.files;
      if (files == null) return;
      widget.onDrop([
        for (var i = 0; i < files.length; i++) _picked(files.item(i)!),
      ]);
    }.toJS;
    web.document.addEventListener('dragover', _over);
    web.document.addEventListener('dragleave', _leave);
    web.document.addEventListener('drop', _drop);
  }

  @override
  void dispose() {
    web.document.removeEventListener('dragover', _over);
    web.document.removeEventListener('dragleave', _leave);
    web.document.removeEventListener('drop', _drop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The File System Access API (Chrome, Edge): a writable stream the device
/// data is written to as it arrives.
Future<(Sink<List<int>>, String)?> recordingSink(
  String suggestedName, {
  String? directory,
}) async {
  if (!web.window.hasProperty('showSaveFilePicker'.toJS).toDart) {
    throw UnsupportedError(
      'Recording needs a browser with the File System Access API '
      '(Chrome or Edge).',
    );
  }
  try {
    final handle = await _showSaveFilePicker(
      _SaveOptions(suggestedName: suggestedName),
    ).toDart;
    final writable = await handle.createWritable().toDart;
    return (_WritableSink(writable), handle.name);
  } catch (_) {
    return null; // cancelled
  }
}

extension type _SaveOptions._(JSObject _) implements JSObject {
  external factory _SaveOptions({String suggestedName});
}

@JS('showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle> _showSaveFilePicker(
  _SaveOptions options,
);

class _WritableSink implements Sink<List<int>> {
  final web.FileSystemWritableFileStream _stream;
  Future<void> _pending = Future.value();

  _WritableSink(this._stream);

  @override
  void add(List<int> data) {
    final bytes = Uint8List.fromList(data).toJS;
    _pending = _pending.then((_) => _stream.write(bytes).toDart);
  }

  @override
  void close() {
    _pending = _pending.then((_) => _stream.close().toDart);
  }
}
