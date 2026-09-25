// Joins a peer_coordinator session over WebRTC and shows this node's role.
//
// Start a hub first (`dart run peer_coordinator:hub --session lab
// --secret-file ./secret`), run this on two or more devices on the same
// network, and pass the hub address and secret with --dart-define:
//
//   flutter run --dart-define=HUB=ws://192.168.1.10:8080 --dart-define=SECRET=...
import 'package:flutter/material.dart';
import 'package:peer_coordinator/websocket.dart' show HubCredentials;
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

const _hub = String.fromEnvironment('HUB', defaultValue: 'ws://localhost:8080');
const _secret = String.fromEnvironment('SECRET');

void main() => runApp(const MaterialApp(home: _RolePage()));

class _RolePage extends StatefulWidget {
  const _RolePage();

  @override
  State<_RolePage> createState() => _RolePageState();
}

class _RolePageState extends State<_RolePage> {
  final _session = PeerSession.create(
    CoordinationConfig(
      name: 'webrtc_example',
      sessionConfig: CoordinationSessionConfig(name: 'lab', maxNodes: 8),
      transportConfig: RtcTransportConfig(
        hubUri: Uri.parse(_hub),
        credentials: HubCredentials(session: 'lab', secret: _secret),
        adapterFactory: flutterWebrtcAdapterFactory,
      ),
    ),
  );
  String _status = 'Joining…';

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      await _session.initialize();
      await _session.join();
      setState(() {
        _status = _session.isCoordinator ? 'Coordinator' : 'Participant';
      });
    } catch (e) {
      setState(() => _status = 'Could not join: $e');
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('webrtc_coordinator_flutter')),
    body: Center(child: Text(_status)),
  );
}
