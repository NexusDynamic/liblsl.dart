Vendored copy of desktop_drop 0.8.4 (https://pub.dev/packages/desktop_drop,
Apache-2.0, see LICENSE; the example app is left out) with the Linux drag
targets reordered in `linux/desktop_drop_plugin.cc`: upstream asks for the
XDG portal transfer key (`application/vnd.portal.filetransfer`) before
`text/uri-list`. File managers such as Dolphin offer both, resolving the
key through the document portal fails with "AccessDenied: Invalid
transfer", and the drop arrives empty. The patched copy asks for URIs
first and uses the portal key only when nothing else is offered. The Dart
code is unchanged.
Remove this copy and the dependency override once upstream is fixed.
