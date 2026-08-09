/// Golden tests for the LSL XPath predicates.
///
/// Discovery in the LSL transport is driven entirely by XPath predicate
/// strings built by [LSLStreamInfoHelper.generatePredicate] and
/// [LSLStreamInfoHelper.generateElectionPredicate]. Those strings are about to
/// be replaced by a typed `DiscoveryQuery` that the LSL transport compiles and
/// other transports evaluate directly.
///
/// These goldens capture the exact string produced at every live call site
/// today, so the new compiler can be proven to emit byte-identical output. A
/// diff here after the refactor is either a bug or a change that must be
/// justified in the same commit.
///
/// No LSL runtime is needed — this is pure string construction.
library;

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

void main() {
  group('generatePredicate — live call sites', () {
    test('connect to coordinator (lsl_coordination_controller.dart:263)', () {
      // Called with a known coordinator uId once one has been identified.
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeUId: 'coordinator-uid',
          nodeRole: 'coordinator',
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "//info/desc/node_uid='coordinator-uid' and "
        "//info/desc/node_role='coordinator'",
      );
    });

    test('connect to any coordinator — nodeUId omitted', () {
      // The same call site passes nodeUId: null when the coordinator is not
      // yet known, which drops the node_uid clause entirely.
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeUId: null,
          nodeRole: 'coordinator',
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "//info/desc/node_role='coordinator'",
      );
    });

    test('node discovery (lsl_coordination_controller.dart:548)', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'coordination',
          sessionName: 'MySession',
          nodeRole: 'participant',
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "//info/desc/node_role='participant'",
      );
    });

    test('createResolvedInletsForStream (lsl_stream.dart:485)', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'TestData',
          sessionName: 'MySession',
        ),
        "starts-with(name, 'TestData') and //info/desc/session='MySession'",
      );
    });

    test('createInletForNode with resolveInfo (lsl_stream.dart:531)', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'TestData',
          sessionName: 'MySession',
          nodeUId: 'node-uid-7',
        ),
        "starts-with(name, 'TestData') and "
        "//info/desc/session='MySession' and "
        "//info/desc/node_uid='node-uid-7'",
      );
    });
  });

  group('generatePredicate — clause coverage', () {
    // Every clause the builder can emit, pinned individually so the compiler
    // rewrite has a complete reference. Several of these are not currently
    // reachable from any call site but are part of the public API.
    test('clause ordering is fixed and independent of argument order', () {
      // The builder appends in a hardcoded sequence, not in the order
      // arguments are supplied. The new compiler must reproduce this or the
      // goldens above will not match.
      expect(
        LSLStreamInfoHelper.generatePredicate(
          nodeRole: 'participant',
          streamNamePrefix: 'coordination',
          sessionName: 'S',
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='S' and "
        "//info/desc/node_role='participant'",
      );
    });

    test('stream name prefix and suffix', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(
          streamNamePrefix: 'a',
          streamNameSuffix: 'b',
        ),
        "starts-with(name, 'a') and ends-with(name, 'b')",
      );
    });

    test('source id prefix, suffix and exclusions', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(sourceIdPrefix: 'p'),
        "starts-with(source_id, 'p')",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(sourceIdSuffix: 's'),
        "ends-with(source_id, 's')",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(excludeSourceId: 'x'),
        "not(source_id='x')",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(excludeSourceIdPrefix: 'x'),
        "not(starts-with(source_id, 'x'))",
      );
    });

    test('desc field equality clauses', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(nodeId: 'n'),
        "//info/desc/node_id='n'",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(nodeUId: 'u'),
        "//info/desc/node_uid='u'",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(nodeCapabilities: 'c'),
        "//info/desc/node_capabilities='c'",
      );
    });

    test('numeric randomRoll comparisons are emitted unquoted', () {
      // Unquoted so XPath compares numerically rather than lexicographically.
      // 0.5 stringifies as "0.5"; integral doubles keep the ".0".
      expect(
        LSLStreamInfoHelper.generatePredicate(randomRollLessThan: 0.5),
        '//info/desc/random_roll < 0.5',
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(randomRollGreaterThan: 1.0),
        '//info/desc/random_roll > 1.0',
      );
    });

    test('timestamp comparisons are quoted (lexicographic on ISO-8601)', () {
      expect(
        LSLStreamInfoHelper.generatePredicate(
          nodeStartedBefore: '2026-08-09T12:00:00.000',
        ),
        "//info/desc/node_started_at < '2026-08-09T12:00:00.000'",
      );
      expect(
        LSLStreamInfoHelper.generatePredicate(
          nodeStartedAfter: '2026-08-09T12:00:00.000',
        ),
        "//info/desc/node_started_at > '2026-08-09T12:00:00.000'",
      );
    });

    test('an empty query throws rather than matching everything', () {
      expect(
        () => LSLStreamInfoHelper.generatePredicate(),
        throwsArgumentError,
      );
    });
  });

  group('generateElectionPredicate — live call site', () {
    test('random strategy (lsl_coordination_controller.dart:146)', () {
      expect(
        LSLStreamInfoHelper.generateElectionPredicate(
          streamName: 'coordination',
          sessionName: 'MySession',
          excludeSourceIdPrefix: 'Node_0',
          isRandomStrategy: true,
          myRandomRoll: 0.42,
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "not(starts-with(source_id, 'Node_0')) and "
        "(//info/desc/node_role='coordinator' or "
        '//info/desc/random_roll < 0.42)',
      );
    });

    test('first strategy uses nodeStartedAt instead of randomRoll', () {
      expect(
        LSLStreamInfoHelper.generateElectionPredicate(
          streamName: 'coordination',
          sessionName: 'MySession',
          excludeSourceIdPrefix: 'Node_0',
          isRandomStrategy: false,
          myStartTime: '2026-08-09T12:00:00.000',
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "not(starts-with(source_id, 'Node_0')) and "
        "(//info/desc/node_role='coordinator' or "
        "//info/desc/node_started_at < '2026-08-09T12:00:00.000')",
      );
    });

    test('with no strategy value, only the coordinator branch remains', () {
      expect(
        LSLStreamInfoHelper.generateElectionPredicate(
          streamName: 'coordination',
          sessionName: 'MySession',
          excludeSourceIdPrefix: 'Node_0',
          isRandomStrategy: true,
          myRandomRoll: null,
        ),
        "starts-with(name, 'coordination') and "
        "//info/desc/session='MySession' and "
        "not(starts-with(source_id, 'Node_0')) and "
        "(//info/desc/node_role='coordinator')",
      );
    });
  });

  group('known issues (characterisation — these pin current behaviour)', () {
    test('election self-exclusion never actually excludes anything', () {
      // generateElectionPredicate is called with
      //   excludeSourceIdPrefix: thisNode.id
      // (lsl_coordination_controller.dart:149) and emits
      //   not(starts-with(source_id, '<nodeId>'))
      //
      // But source_id is built as
      //   '<streamName>//<role>//<uId>//<nodeId>'
      // (lsl_stream.dart:64), so it begins with the *stream name*. A node id
      // is never a prefix of it, and the clause is therefore always true.
      //
      // It is inert today: a node cannot match the OR branch against itself
      // anyway, because at election time its own role is still 'none' and its
      // roll is not strictly less than itself. But re-expressing this as a
      // typed `excludeNodeUId` term will produce a clause that *does* match,
      // which is a deliberate behaviour change, not an accident.
      const nodeId = 'Node_0';
      final sourceId = LSLStreamInfoHelper.generateSourceID(
        CoordinationStreamConfig(name: 'coordination'),
        node: ParticipantNode(
          NodeConfig(name: nodeId, id: nodeId, uId: 'uid-0'),
        ),
      );

      expect(sourceId, 'coordination//participant//uid-0//$nodeId');
      expect(
        sourceId.startsWith(nodeId),
        isFalse,
        reason:
            'BUG: the exclusion clause tests a prefix that source_id can '
            'never have',
      );
    });
  });
}
