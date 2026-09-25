/// Fallback for platforms with neither `dart:io` nor a browser console.
///
/// Assume no ANSI support: unrendered escape codes are worse than plain text.
bool get ansiSupported => false;
