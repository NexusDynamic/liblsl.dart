import 'package:flutter/widgets.dart';

import 'files.dart';

Future<List<PickedFile>> pickFiles(
  List<String> extensions, {
  String? initialDirectory,
}) async => const [];

PickedFile? fileAtPath(String path) => null;

bool get supportsPaths => false;

Widget fileDropTarget({
  required Widget child,
  required void Function(List<PickedFile> files) onDrop,
  required void Function(bool hovering, bool acceptable) onHover,
}) => child;

Future<(Sink<List<int>>, String)?> recordingSink(
  String suggestedName, {
  String? directory,
}) async => null;
