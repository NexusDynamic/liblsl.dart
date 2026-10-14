import 'dart:io';

Future<String> readText(String path) => File(path).readAsString();

Future<void> writeText(String path, String text) =>
    File(path).writeAsString(text);
