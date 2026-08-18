/// Tests the fake, not the transport.
///
/// Everything else in this package is tested against this fake, so a fake that
/// lies makes the whole suite meaningless. These pin the properties the rest of
/// the suite depends on: asynchronous delivery, a negotiation that is a real
/// handshake, candidate buffering, and channels that only open when the link
/// does.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_coordinator/testing.dart';
import 'package:webrtc_coordinator/transports/webrtc.dart';

void main() {
  late FakeRtcBus bus;
  late FakeRtcPeerAdapter alice;
  late FakeRtcPeerAdapter bob;

  setUp(() {
    bus = FakeRtcBus();
    alice = FakeRtcPeerAdapter(selfKey: 'alice', bus: bus);
    bob = FakeRtcPeerAdapter(selfKey: 'bob', bus: bus);
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
  });

  /// Drives a full offer/answer/candidate exchange, as the transport will.
  Future<(RtcPeerLink, RtcPeerLink)> connected() async {
    final a = await alice.createLink('bob');
    final b = await bob.createLink('alice');

    final aCandidates = <Map<String, Object?>>[];
    final bCandidates = <Map<String, Object?>>[];
    a.localCandidates.listen(aCandidates.add);
    b.localCandidates.listen(bCandidates.add);

    final offer = await a.createOffer();
    final answer = await b.createAnswer(offer);
    await a.acceptAnswer(answer);

    // Let the candidate deliveries land, then cross them over.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (final c in aCandidates) {
      await b.addCandidate(c);
    }
    for (final c in bCandidates) {
      await a.addCandidate(c);
    }
    return (a, b);
  }

  group('negotiation is a real handshake', () {
    test('a link does not connect until the answer comes back', () async {
      final a = await alice.createLink('bob');
      final b = await bob.createLink('alice');

      expect(a.state, RtcLinkState.connecting);
      final offer = await a.createOffer();
      expect(
        a.state,
        RtcLinkState.connecting,
        reason: 'an offer alone connects nothing',
      );

      final answer = await b.createAnswer(offer);
      expect(b.state, RtcLinkState.connected);
      expect(a.state, RtcLinkState.connecting);

      await a.acceptAnswer(answer);
      expect(a.state, RtcLinkState.connected);
    });

    test('an answer without an offer is refused', () async {
      final a = await alice.createLink('bob');
      expect(
        () => a.acceptAnswer({'type': 'answer', 'sdp': 'x'}),
        throwsStateError,
      );
    });

    test(
      'candidates arriving before the remote description are buffered',
      () async {
        // The failure mode this guards: dropping early candidates works on a
        // fast LAN and fails behind any real latency.
        final b = await bob.createLink('alice');
        await b.addCandidate({'candidate': 'early-1'});
        await b.addCandidate({'candidate': 'early-2'});

        final a = await alice.createLink('bob');
        final offer = await a.createOffer();
        await b.createAnswer(offer);

        expect((b as dynamic).acceptedCandidates, hasLength(2));
      },
    );
  });

  group('delivery is asynchronous', () {
    test('a sent message has not arrived by the next statement', () async {
      final (a, b) = await connected();
      final ca = await a.openChannel(600);
      final cb = await b.openChannel(600);
      await ca.ready;
      await cb.ready;

      final received = <Object>[];
      cb.messages.listen(received.add);

      ca.send('hello');
      expect(
        received,
        isEmpty,
        reason: 'synchronous delivery would hide every ordering bug',
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, ['hello']);
    });

    test('binary payloads cross unchanged', () async {
      final (a, b) = await connected();
      final ca = await a.openChannel(601);
      final cb = await b.openChannel(601);
      await ca.ready;
      await cb.ready;

      final received = <Object>[];
      cb.messages.listen(received.add);

      ca.send(Uint8List.fromList([1, 2, 3, 250]));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(received.single, isA<Uint8List>());
      expect(received.single, [1, 2, 3, 250]);
    });

    test('ordering is preserved across a burst', () async {
      final (a, b) = await connected();
      final ca = await a.openChannel(602);
      final cb = await b.openChannel(602);
      await ca.ready;
      await cb.ready;

      final received = <Object>[];
      cb.messages.listen(received.add);

      for (var i = 0; i < 20; i++) {
        ca.send('m$i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, [for (var i = 0; i < 20; i++) 'm$i']);
    });

    test('a payload that is neither String nor bytes is refused', () async {
      final (a, _) = await connected();
      final ca = await a.openChannel(603);
      await ca.ready;
      expect(() => ca.send(42), throwsArgumentError);
    });
  });

  group('channels follow the link', () {
    test(
      'a channel opened before connection becomes ready on connect',
      () async {
        final a = await alice.createLink('bob');
        final b = await bob.createLink('alice');

        final ca = await a.openChannel(604);
        expect(ca.isOpen, isFalse);

        final offer = await a.createOffer();
        final answer = await b.createAnswer(offer);
        await a.acceptAnswer(answer);

        await ca.ready;
        expect(ca.isOpen, isTrue);
      },
    );

    test('the same id returns the same channel', () async {
      final (a, _) = await connected();
      final first = await a.openChannel(605);
      final second = await a.openChannel(605);
      expect(identical(first, second), isTrue);
    });

    test('closing the link closes its channels and stops delivery', () async {
      final (a, b) = await connected();
      final ca = await a.openChannel(606);
      final cb = await b.openChannel(606);
      await ca.ready;
      await cb.ready;

      final received = <Object>[];
      cb.messages.listen(received.add);

      await a.close();
      expect(a.state, RtcLinkState.closed);
      expect(ca.isOpen, isFalse);

      ca.send('after-close');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, isEmpty);
    });

    test(
      'sending on a channel whose peer never opened one is a no-op',
      () async {
        final (a, _) = await connected();
        final ca = await a.openChannel(607);
        await ca.ready;
        // No matching channel on bob's side; must not throw.
        ca.send('into the void');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      },
    );

    test(
      'reliability options are recorded so the transport can be checked',
      () async {
        final (a, _) = await connected();
        final channel = await a.openChannel(
          608,
          ordered: false,
          maxRetransmits: 0,
        );
        expect((channel as dynamic).ordered, isFalse);
        expect((channel as dynamic).maxRetransmits, 0);
      },
    );
  });

  group('channel id derivation', () {
    test('the coordination stream is pinned', () {
      expect(rtcChannelIdFor(coordinationChannelName), coordinationChannelId);
    });

    test('is deterministic and stays out of the reserved range', () {
      for (final name in ['Data', 'Modes-17', 'a', 'x' * 200]) {
        final id = rtcChannelIdFor(name);
        expect(id, rtcChannelIdFor(name), reason: 'must be stable');
        expect(id, greaterThanOrEqualTo(reservedChannelIds));
        expect(id, lessThanOrEqualTo(maxChannelId));
      }
    });

    test('different names generally get different ids', () {
      final ids = {for (var i = 0; i < 500; i++) rtcChannelIdFor('stream-$i')};
      // Not a guarantee — see the doc comment. This pins that the hash is not
      // pathologically bad, which is a different claim from collision-free.
      expect(ids.length, greaterThan(480));
    });
  });
}
