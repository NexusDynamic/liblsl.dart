// Web-safety check for the lsl_tools facade.
//
// Compile this to JavaScript to prove that what the viewer uses in a browser
// (the LSL facade, the bridge client, the republisher and the server facade)
// never reaches dart:io or dart:ffi:
//
//   dart compile js -o /tmp/lsl_tools_web_check.js tool/web_safety_check.dart
//
// `package:lsl_tools/cli.dart` is native only and deliberately not imported.
import 'package:lsl_tools/lsl_tools.dart';

void main() {
  print(
    [
      lsl.supported,
      LslBridgeServer.supported,
      LslBridgeServer.relaySupported,
      LslBridgeClient.connect,
      LslBridgeRepublisher.start,
      LslRecorder.start,
    ].length,
  );
}
