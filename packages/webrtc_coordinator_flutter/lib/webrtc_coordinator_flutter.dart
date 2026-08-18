/// The `flutter_webrtc` binding for `webrtc_coordinator`.
///
/// One import, one line of configuration:
///
/// ```dart
/// import 'package:webrtc_coordinator/transports/webrtc.dart';
/// import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';
///
/// final config = CoordinationConfig(
///   transportConfig: RtcTransportConfig(
///     hubUri: Uri.parse('ws://hub.local:8080'),
///     adapterFactory: flutterWebrtcAdapterFactory,
///   ),
/// );
/// ```
///
/// Everything else — the transport, the streams, the mesh — comes from
/// `webrtc_coordinator`, which is pure Dart. This package exists only because
/// `flutter_webrtc` is a plugin with native code, and a package that depends on
/// it cannot be tested in a headless `dart test` VM or used from a non-Flutter
/// entry point.
library;

export 'package:webrtc_coordinator/transports/webrtc.dart';
export 'package:webrtc_coordinator/webrtc_coordinator.dart';

export 'src/flutter_rtc_adapter.dart'
    show FlutterRtcPeerAdapter, flutterWebrtcAdapterFactory;
