import 'dart:io';

/// Terminals may support ANSI colour; ask the platform.
bool get ansiSupported => stdout.supportsAnsiEscapes;
