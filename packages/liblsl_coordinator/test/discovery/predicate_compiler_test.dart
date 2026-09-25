/// Proves the [DiscoveryQuery] → XPath compiler reproduces exactly what the
/// original string builder emitted.
///
/// The goldens in `test/characterisation/predicate_golden_test.dart` pin the
/// old output; this file compiles the equivalent typed queries and asserts
/// byte-identical results, so the LSL transport's on-the-wire behaviour is
/// provably unchanged by the refactor.
library;

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

void main() {
  group('compiles to the same XPath as the original builder', () {
    test('connect to a known coordinator', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.coordinator(
            streamName: 'coordination',
            sessionName: 'MySession',
            coordinatorUId: 'coordinator-uid',
          ),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeUId: 'coordinator-uid',
          nodeRole: 'coordinator',
        ),
      );
    });

    test('connect to any coordinator', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.coordinator(
            streamName: 'coordination',
            sessionName: 'MySession',
          ),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeRole: 'coordinator',
        ),
      );
    });

    test('participant discovery', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.participants(
            streamName: 'coordination',
            sessionName: 'MySession',
          ),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeRole: 'participant',
        ),
      );
    });

    test('stream publishers, with and without a node filter', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.streamPublishers(
            streamName: 'TestData',
            sessionName: 'MySession',
          ),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'TestData',
          sessionName: 'MySession',
        ),
      );
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.streamPublishers(
            streamName: 'TestData',
            sessionName: 'MySession',
            nodeUId: 'node-uid-7',
          ),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'TestData',
          sessionName: 'MySession',
          nodeUId: 'node-uid-7',
        ),
      );
    });

    test('every clause type round-trips to the same string', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.peers(streamNamePrefix: 'a', streamNameSuffix: 'b'),
        ),
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'a',
          streamNameSuffix: 'b',
        ),
      );
      expect(
        LslPredicateCompiler.compile(PeerQueries.peers(nodeId: 'n')),
        LSLStreamInfoHelper.generatePredicate(nodeId: 'n'),
      );
      expect(
        LslPredicateCompiler.compile(PeerQueries.peers(capabilities: 'c')),
        LSLStreamInfoHelper.generatePredicate(nodeCapabilities: 'c'),
      );
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.peers(randomRollLessThan: 0.5),
        ),
        LSLStreamInfoHelper.generatePredicate(randomRollLessThan: 0.5),
      );
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.peers(randomRollGreaterThan: 1.0),
        ),
        LSLStreamInfoHelper.generatePredicate(randomRollGreaterThan: 1.0),
      );
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.peers(startedBefore: '2026-08-09T12:00:00.000'),
        ),
        LSLStreamInfoHelper.generatePredicate(
          nodeStartedBefore: '2026-08-09T12:00:00.000',
        ),
      );
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.peers(startedAfter: '2026-08-09T12:00:00.000'),
        ),
        LSLStreamInfoHelper.generatePredicate(
          nodeStartedAfter: '2026-08-09T12:00:00.000',
        ),
      );
    });

    test('the election query keeps its exact shape', () {
      // Structurally identical to the original, including the parenthesised
      // OR branch. The only difference is the self-exclusion clause, which is
      // asserted separately below because it is a deliberate fix.
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.election(
            streamName: 'coordination',
            sessionName: 'MySession',
            excludeNodeUId: 'my-uid',
            isRandomStrategy: true,
            myRandomRoll: 0.42,
          ),
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "not(//info/desc/node_uid='my-uid') and "
        "(//info/desc/node_role='coordinator' or "
        '//info/desc/random_roll < 0.42)',
      );
    });

    test('the first-strategy election query keeps its exact shape', () {
      expect(
        LslPredicateCompiler.compile(
          PeerQueries.election(
            streamName: 'coordination',
            sessionName: 'MySession',
            excludeNodeUId: 'my-uid',
            isRandomStrategy: false,
            myStartTime: '2026-08-09T12:00:00.000',
          ),
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "not(//info/desc/node_uid='my-uid') and "
        "(//info/desc/node_role='coordinator' or "
        "//info/desc/node_started_at < '2026-08-09T12:00:00.000')",
      );
    });
  });

  group('the deliberate behaviour change', () {
    test('self-exclusion now excludes by uId and actually works', () {
      // Before: not(starts-with(source_id, '<nodeId>')) — always true, because
      // source_id starts with the stream name.
      // After:  not(//info/desc/node_uid='<uId>') — genuinely excludes self.
      final compiled = LslPredicateCompiler.compile(
        PeerQueries.election(
          streamName: 'coordination',
          sessionName: 'S',
          excludeNodeUId: 'my-uid',
          isRandomStrategy: true,
          myRandomRoll: 0.5,
        ),
      );
      expect(compiled, contains("not(//info/desc/node_uid='my-uid')"));
      expect(compiled, isNot(contains('source_id')));
    });

    test('and the typed query rejects self locally too', () {
      final query = PeerQueries.election(
        streamName: 'coordination',
        sessionName: 'S',
        excludeNodeUId: 'my-uid',
        isRandomStrategy: true,
        myRandomRoll: 0.5,
      );
      // A peer that is me: excluded even though it would otherwise match.
      expect(query.matches(_peer(uId: 'my-uid', role: 'coordinator')), isFalse);
      // The same peer under a different identity: matched.
      expect(query.matches(_peer(uId: 'other', role: 'coordinator')), isTrue);
    });
  });

  group('XPath literal quoting (previously unescaped)', () {
    test('plain values use single quotes', () {
      expect(LslPredicateCompiler.xpathLiteral('plain'), "'plain'");
    });

    test('a value containing an apostrophe switches to double quotes', () {
      // The old builder produced //info/desc/session='Bob's', which is
      // malformed XPath and resolves to nothing.
      expect(LslPredicateCompiler.xpathLiteral("Bob's"), '"Bob\'s"');
      expect(
        LslPredicateCompiler.compile(PeerQueries.peers(sessionName: "Bob's")),
        '//info/desc/session="Bob\'s"',
      );
    });

    test('a value containing a double quote uses single quotes', () {
      expect(LslPredicateCompiler.xpathLiteral('say "hi"'), '\'say "hi"\'');
    });

    test('a value containing both falls back to concat()', () {
      expect(
        LslPredicateCompiler.xpathLiteral('it\'s "x"'),
        'concat(\'it\', "\'", \'s "x"\')',
      );
    });
  });

  group('queries LSL cannot express are refused, not widened', () {
    test('a match-all query throws', () {
      expect(
        () => LslPredicateCompiler.compile(const AlwaysMatch()),
        throwsArgumentError,
      );
      // PeerQueries.peers() with no arguments is a match-all.
      expect(
        () => LslPredicateCompiler.compile(PeerQueries.peers()),
        throwsArgumentError,
      );
    });

    test('an empty disjunction throws rather than matching everything', () {
      expect(
        () => LslPredicateCompiler.compile(const OrQuery([])),
        throwsArgumentError,
      );
    });
  });
}

PeerDescriptor _peer({
  String uId = 'uid',
  String role = 'participant',
  String stream = 'coordination',
  String session = 'S',
  double? roll,
}) => PeerDescriptor(
  streamName: stream,
  sessionName: session,
  nodeId: 'node',
  nodeUId: uId,
  nodeRole: role,
  randomRoll: roll,
  endpointId: '$session/$uId/$stream',
);
