/// The hub's security boundary, as executable assertions.
///
/// Every test here reproduces something that worked against the hub before it
/// authenticated anyone: reading the peer directory anonymously, taking over
/// another peer's endpoint, subscribing to somebody else's stream, and making
/// the hub buffer a frame sized to exhaust it. They are written as attacks
/// rather than as feature tests because that is the only way the assertions
/// stay honest — each one fails loudly if the corresponding check is removed.
///
/// The raw socket is deliberate. Going through `WsConnection` would test the
/// hub against a well-behaved client, which is precisely the case that was
/// never in doubt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/testing.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:test/test.dart';

const _session = 'SecuritySession';
const _secret = 'correct-horse-battery-staple';

Map<String, dynamic> _descriptor({
  required String uid,
  String stream = 'coordination',
  String? endpointId,
}) => {
  'streamName': stream,
  'sessionName': _session,
  'nodeId': 'node-$uid',
  'nodeUId': uid,
  'nodeRole': 'participant',
  'endpointId': endpointId ?? '$_session/$uid/$stream',
  'capabilities': <String>[],
  'extra': <String, String>{},
};

/// A raw socket with the frames it has received, and no client-side manners.
class _Raw {
  _Raw(this.socket) {
    socket.listen(
      (Object? data) {
        if (data is String) {
          received.add(jsonDecode(data) as Map<String, dynamic>);
        }
      },
      onDone: () => closed.complete(),
      onError: (Object _) {},
      cancelOnError: true,
    );
  }

  final WebSocket socket;
  final List<Map<String, dynamic>> received = [];
  final Completer<void> closed = Completer<void>();

  Iterable<Map<String, dynamic>> ofType(WsControl type) =>
      received.where((f) => f['t'] == type.name);

  Map<String, dynamic>? get challenge => ofType(WsControl.challenge).isEmpty
      ? null
      : ofType(WsControl.challenge).first['p'] as Map<String, dynamic>;

  void send(String type, Map<String, dynamic> payload) =>
      socket.add(jsonEncode({'v': wsProtocolVersion, 't': type, 'p': payload}));

  /// Answers the challenge, optionally getting it wrong on purpose.
  void authenticate(
    String nodeUId, {
    String secret = _secret,
    String session = _session,
    int? epoch,
    String? proof,
  }) {
    final issued = challenge!;
    send('auth', {
      'session': session,
      'epoch': epoch ?? issued['epoch'],
      'nodeUId': nodeUId,
      'proof':
          proof ??
          HubCredentials.computeProof(
            secret: secret,
            nonce: issued['nonce'] as String,
            session: session,
            epoch: epoch ?? issued['epoch'] as int,
            nodeUId: nodeUId,
          ),
    });
  }

  bool get authenticated => ofType(WsControl.authOk).isNotEmpty;
}

Future<void> _settle([int ms = 200]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late TestHub testHub;
  late CoordinationHub hub;
  final open = <_Raw>[];

  Future<_Raw> dial() async {
    final raw = _Raw(await WebSocket.connect(testHub.uri.toString()));
    open.add(raw);
    await _settle(100); // let the challenge arrive
    return raw;
  }

  /// A fully authenticated, registered peer.
  Future<_Raw> peer(String uid, {String stream = 'coordination'}) async {
    final raw = await dial();
    raw.authenticate(uid);
    await _settle(100);
    raw.send('hello', {'peer': _descriptor(uid: uid, stream: stream)});
    await _settle(100);
    return raw;
  }

  setUp(() async {
    testHub = await startTestHub(session: _session, secret: _secret);
    hub = testHub.hub;
  });

  tearDown(() async {
    for (final raw in open) {
      await raw.socket.close();
    }
    open.clear();
    await testHub.close();
  });

  group('the door', () {
    test('a fresh connection is challenged and nothing else', () async {
      final raw = await dial();
      expect(raw.challenge, isNotNull);
      expect(raw.challenge!['nonce'], isA<String>());
      expect(raw.challenge!['epoch'], hub.epoch);
      expect(raw.authenticated, isFalse);
      expect(hub.connectionCount, 0, reason: 'not a client until it proves it');
      expect(hub.pendingCount, 1);
    });

    test('an anonymous query returns nothing and closes the socket', () async {
      // Exploit #1: this used to dump every peer's descriptor to anyone who
      // could open a socket.
      await peer('victim');
      final attacker = await dial();
      attacker.send('query', {
        'qid': 1,
        'query': {'op': 'and', 'terms': <dynamic>[]},
      });
      await _settle();

      expect(attacker.ofType(WsControl.queryResult), isEmpty);
      expect(attacker.socket.closeCode, HubCloseCode.unauthorized);
    });

    test('every pre-auth frame type is refused, not just query', () async {
      for (final type in ['hello', 'subscribe', 'message', 'signal']) {
        final attacker = await dial();
        attacker.send(type, {'anything': true});
        await _settle(100);
        expect(
          attacker.socket.closeCode,
          HubCloseCode.unauthorized,
          reason: '$type must not be honoured before auth',
        );
      }
      expect(hub.connectionCount, 0);
    });

    test('a wrong secret is refused', () async {
      final attacker = await dial();
      attacker.authenticate('attacker', secret: 'not-the-secret');
      await _settle();
      expect(attacker.authenticated, isFalse);
      expect(attacker.socket.closeCode, HubCloseCode.unauthorized);
    });

    test('a proof for the wrong session is refused', () async {
      final attacker = await dial();
      attacker.authenticate('attacker', session: 'SomeOtherSession');
      await _settle();
      expect(attacker.authenticated, isFalse);
      expect(attacker.socket.closeCode, HubCloseCode.unauthorized);
    });

    test('a proof from another epoch is refused', () async {
      final attacker = await dial();
      attacker.authenticate('attacker', epoch: hub.epoch + 5);
      await _settle();
      expect(attacker.authenticated, isFalse);
      expect(attacker.socket.closeCode, HubCloseCode.sessionClosed);
    });

    test('a captured proof cannot be replayed on a new connection', () async {
      final honest = await dial();
      final issued = honest.challenge!;
      final stolen = HubCredentials.computeProof(
        secret: _secret,
        nonce: issued['nonce'] as String,
        session: _session,
        epoch: issued['epoch'] as int,
        nodeUId: 'honest',
      );
      honest.authenticate('honest');
      await _settle(100);
      expect(honest.authenticated, isTrue);

      // Same proof, different connection: the nonce it was computed over is
      // not the one this connection was issued.
      final attacker = await dial();
      attacker.authenticate('honest', proof: stolen);
      await _settle();
      expect(attacker.authenticated, isFalse);
      expect(attacker.socket.closeCode, HubCloseCode.unauthorized);
    });

    test(
      'a silent connection is dropped after the handshake timeout',
      () async {
        await testHub.close();
        testHub = await startTestHub(
          session: _session,
          secret: _secret,
          limits: const WsLimits(handshakeTimeout: Duration(milliseconds: 200)),
        );
        hub = testHub.hub;

        final loiterer = await dial();
        expect(hub.pendingCount, 1);
        await _settle(400);
        expect(loiterer.socket.closeCode, HubCloseCode.unauthorized);
        expect(hub.pendingCount, 0);
      },
    );
  });

  group('identity', () {
    test('an authenticated peer cannot claim another node\'s endpoint', () async {
      // Exploit #2: `hello` with the victim's endpointId and publish:false used
      // to de-register the victim in one frame, after which the attacker could
      // speak as it.
      await peer('victim');
      expect(hub.endpointCount, 1);

      final attacker = await dial();
      attacker.authenticate('attacker');
      await _settle(100);
      attacker.send('hello', {
        'peer': _descriptor(uid: 'attacker')
          ..['endpointId'] = '$_session/victim/coordination',
        'publish': false,
      });
      await _settle();

      expect(
        hub.endpointCount,
        1,
        reason: 'the victim must still be registered',
      );
      expect(
        hub.subscribersFor(
          streamName: 'coordination',
          producerEndpointId: '$_session/victim/coordination',
        ),
        isEmpty,
      );
      expect(attacker.ofType(WsControl.welcome), isEmpty);
    });

    test('a descriptor for another node is refused', () async {
      final attacker = await dial();
      attacker.authenticate('attacker');
      await _settle(100);
      // Consistent, self-referential descriptor — but for a node this
      // connection did not authenticate as.
      attacker.send('hello', {'peer': _descriptor(uid: 'victim')});
      await _settle();

      expect(hub.endpointCount, 0);
      expect(attacker.ofType(WsControl.welcome), isEmpty);
    });

    test('a peer cannot relay a message as another peer', () async {
      final victim = await peer('victim');
      final attacker = await peer('attacker');
      // Subscribe the victim to its own stream so a successful spoof would be
      // visible.
      victim.send('subscribe', {
        'stream': 'coordination',
        'subscriber': '$_session/victim/coordination',
        'from': ['$_session/victim/coordination'],
      });
      await _settle(100);

      attacker.send('message', {
        'stream': 'coordination',
        'from': '$_session/victim/coordination',
        'payload': {'spoofed': true},
      });
      await _settle();

      expect(
        victim.ofType(WsControl.message),
        isEmpty,
        reason: 'the hub must not relay a message attributed to another peer',
      );
    });

    test(
      'a reconnect evicts the stale socket rather than coexisting',
      () async {
        final first = await peer('rejoiner');
        expect(hub.connectionCount, 1);

        final second = await dial();
        second.authenticate('rejoiner');
        await _settle();

        expect(second.authenticated, isTrue);
        expect(first.socket.closeCode, HubCloseCode.identityConflict);
        expect(hub.connectionCount, 1, reason: 'one node, one socket');
      },
    );
  });

  group('frame size', () {
    test('an oversized frame kills the connection, not the hub', () async {
      // Exploit #4: a single 128 MB frame took hub RSS from 150 MB to 417 MB.
      //
      // The assertion is behavioural rather than a memory measurement. RSS
      // cannot be measured meaningfully from here: the attacker runs in this
      // same process, and its own multi-megabyte string plus the bytes the
      // WebSocket encoder makes of it dominate anything the hub might
      // allocate. What is checkable in-process is that the cap is plumbed
      // through with the right value and that a violation costs only the
      // offending connection.
      //
      // That rejecting costs *nothing* rests on where the SDK enforces the
      // limit — `_lengthDone` in `websocket_impl.dart`, at the frame's length
      // header, before any payload is read — not on this test.
      await testHub.close();
      testHub = await startTestHub(
        session: _session,
        secret: _secret,
        limits: const WsLimits(maxFrameBytes: 64 * 1024),
      );
      hub = testHub.hub;

      final attacker = await dial();
      expect(hub.pendingCount, 1);
      attacker.socket.add('x' * (1024 * 1024));
      await _settle(800);

      expect(hub.pendingCount, 0, reason: 'the offending connection is gone');
      await expectLater(attacker.closed.future, completes);

      // And the hub still serves everyone else.
      final honest = await peer('honest');
      expect(honest.authenticated, isTrue);
      expect(hub.endpointCount, 1);
    });

    test('a frame just under the cap is accepted', () async {
      // The other half of the previous test: without this, a cap of zero would
      // pass just as well.
      await testHub.close();
      testHub = await startTestHub(
        session: _session,
        secret: _secret,
        limits: const WsLimits(maxFrameBytes: 64 * 1024),
      );
      hub = testHub.hub;

      final honest = await dial();
      honest.authenticate('honest');
      await _settle(100);
      honest.send('hello', {
        'peer': _descriptor(uid: 'honest')
          // Padding an ignored field, to get the frame near the cap without
          // depending on any particular field being large.
          ..['extra'] = {'padding': 'z' * (48 * 1024)},
      });
      await _settle(300);

      expect(hub.endpointCount, 1);
      expect(honest.closed.isCompleted, isFalse);
    });

    test('a client refuses to send a frame the hub would reject', () async {
      final connection = await testHub.connect('sender', maxFrameBytes: 4096);
      expect(
        () => connection.publishMessage(
          streamName: 'coordination',
          fromEndpointId: '$_session/sender/coordination',
          payload: {'padding': 'y' * 8192},
        ),
        throwsA(isA<WsFrameTooLargeException>()),
        reason: 'the failure belongs at the call site, not at the hub',
      );
      await connection.close();
    });
  });

  group('session lifecycle', () {
    test('ending a session disconnects everyone and bars the door', () async {
      final participant = await peer('participant');
      expect(hub.connectionCount, 1);

      await hub.endSession(reason: 'experiment over');
      await _settle();

      expect(participant.socket.closeCode, HubCloseCode.sessionClosed);
      expect(hub.connectionCount, 0);
      expect(hub.endpointCount, 0);
      expect(hub.status, HubSessionStatus.closed);

      // Valid credentials, closed door.
      await expectLater(
        WebSocket.connect(testHub.uri.toString()),
        throwsA(isA<Object>()),
        reason: 'a closed hub refuses the upgrade outright',
      );
    });

    test('reopening with a rotated secret locks out the old cohort', () async {
      await peer('participant');
      await hub.endSession();
      hub.openSession(secret: 'a-brand-new-secret');
      await _settle(100);

      // The old secret no longer proves anything.
      final returning = await dial();
      returning.authenticate('participant', secret: _secret);
      await _settle();
      expect(returning.authenticated, isFalse);
      expect(returning.socket.closeCode, HubCloseCode.unauthorized);

      // The new one does.
      final admitted = await dial();
      admitted.authenticate('newcomer', secret: 'a-brand-new-secret');
      await _settle();
      expect(admitted.authenticated, isTrue);
    });

    test('revoking one node leaves the rest of the session alone', () async {
      final kept = await peer('kept');
      await peer('unwanted');
      expect(hub.connectionCount, 2);

      await hub.revoke('unwanted');
      await _settle();

      expect(hub.connectionCount, 1);
      expect(kept.socket.closeCode, isNull, reason: 'unaffected');

      final returning = await dial();
      returning.authenticate('unwanted');
      await _settle();
      expect(returning.authenticated, isFalse);
      expect(returning.socket.closeCode, HubCloseCode.sessionClosed);
    });

    test('a session ttl ends the session on its own', () async {
      await testHub.close();
      testHub = await startTestHub(
        session: _session,
        secret: _secret,
        // Comfortably longer than the ~300ms of settling `peer` needs, or the
        // session would already be over before anyone joined it.
        sessionTtl: const Duration(milliseconds: 1200),
      );
      hub = testHub.hub;

      final participant = await peer('participant');
      expect(hub.status, HubSessionStatus.open);
      await _settle(1200);

      expect(hub.status, HubSessionStatus.closed);
      expect(participant.socket.closeCode, HubCloseCode.sessionClosed);
    });
  });

  group('resource caps', () {
    test('the hub refuses connections past its limit', () async {
      await testHub.close();
      testHub = await startTestHub(
        session: _session,
        secret: _secret,
        limits: const WsLimits(maxConnections: 2),
      );
      hub = testHub.hub;

      await dial();
      await dial();
      await expectLater(
        WebSocket.connect(testHub.uri.toString()),
        throwsA(isA<Object>()),
        reason: 'the third connection is refused before the upgrade',
      );
    });

    test('a peer cannot register endpoints without bound', () async {
      await testHub.close();
      testHub = await startTestHub(
        session: _session,
        secret: _secret,
        limits: const WsLimits(maxEndpointsPerConnection: 3),
      );
      hub = testHub.hub;

      final greedy = await dial();
      greedy.authenticate('greedy');
      await _settle(100);
      for (var i = 0; i < 10; i++) {
        greedy.send('hello', {
          'peer': _descriptor(uid: 'greedy', stream: 'stream-$i'),
        });
      }
      await _settle();

      expect(hub.endpointCount, 3);
    });
  });
}
