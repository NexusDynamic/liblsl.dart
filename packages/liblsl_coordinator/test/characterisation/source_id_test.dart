/// Characterisation tests for LSL peer identity encoding.
///
/// The LSL transport encodes node identity positionally into the stream's
/// `source_id`:
///
///     '<streamName>//<role>//<nodeUId>//<nodeId>'
///
/// Discovery then parses it back out. That format is about to be wrapped in a
/// typed `PeerDescriptor`, but the on-the-wire string must stay byte-identical
/// so a node running the new code can still discover one running the old.
library;

import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:test/test.dart';

Node participant({
  String name = 'Node_0',
  String id = 'Node_0',
  String uId = 'uid-0',
}) => ParticipantNode(NodeConfig(name: name, id: id, uId: uId));

void main() {
  group('generateSourceID', () {
    test('emits streamName//role//uId//nodeId', () {
      expect(
        LSLStreamInfoHelper.generateSourceID(
          CoordinationStreamConfig(name: 'coordination'),
          node: participant(),
        ),
        'coordination//participant//uid-0//Node_0',
      );
    });

    test('reflects the node role, which changes on promotion', () {
      final config = NodeConfig(name: 'N', id: 'N', uId: 'u');
      final streamConfig = CoordinationStreamConfig(name: 'coordination');

      expect(
        LSLStreamInfoHelper.generateSourceID(
          streamConfig,
          node: CoordinatorNode(config),
        ),
        'coordination//coordinator//u//N',
      );
      // An unpromoted node still reports role 'none' — this is why the outlet
      // has to be recreated after election.
      expect(
        LSLStreamInfoHelper.generateSourceID(
          streamConfig,
          node: Node(NodeConfig(name: 'N', id: 'N', uId: 'u')),
        ),
        'coordination//none//u//N',
      );
    });

    test('uses the data stream name for data streams', () {
      expect(
        LSLStreamInfoHelper.generateSourceID(
          DataStreamConfig(
            name: 'TestData',
            channels: 3,
            sampleRate: 10.0,
            dataType: StreamDataType.double64,
          ),
          node: participant(),
        ),
        'TestData//participant//uid-0//Node_0',
      );
    });
  });

  group('parseSourceId', () {
    test('round-trips everything generateSourceID produces', () {
      final node = participant(id: 'Node_7', uId: 'uid-7');
      final sourceId = LSLStreamInfoHelper.generateSourceID(
        CoordinationStreamConfig(name: 'coordination'),
        node: node,
      );

      final parsed = LSLStreamInfoHelper.parseSourceId(sourceId);
      expect(parsed[LSLStreamInfoHelper.streamNameKey], 'coordination');
      expect(parsed[LSLStreamInfoHelper.nodeRoleKey], 'participant');
      expect(parsed[LSLStreamInfoHelper.nodeUIdKey], 'uid-7');
      expect(parsed[LSLStreamInfoHelper.nodeIdKey], 'Node_7');
    });

    test('rejects strings with fewer than four segments', () {
      expect(
        () => LSLStreamInfoHelper.parseSourceId('a//b//c'),
        throwsFormatException,
      );
      expect(
        () => LSLStreamInfoHelper.parseSourceId('not-a-source-id'),
        throwsFormatException,
      );
      expect(
        () => LSLStreamInfoHelper.parseSourceId(''),
        throwsFormatException,
      );
    });
  });

  group('known issues (characterisation — these pin current behaviour)', () {
    test('a node id containing the separator corrupts parsing', () {
      // The format is positional with no escaping, so any '/' in a node id,
      // name or role shifts every field. parseSourceId takes parts[1..3] and
      // ignores the rest, so extra segments are silently dropped rather than
      // rejected.
      final node = participant(id: 'weird//id', uId: 'uid-0');
      final sourceId = LSLStreamInfoHelper.generateSourceID(
        CoordinationStreamConfig(name: 'coordination'),
        node: node,
      );
      expect(sourceId, 'coordination//participant//uid-0//weird//id');

      final parsed = LSLStreamInfoHelper.parseSourceId(sourceId);
      expect(
        parsed[LSLStreamInfoHelper.nodeIdKey],
        'weird',
        reason: 'BUG: the node id is truncated at the embedded separator',
      );
    });

    test('a stream name containing the separator corrupts every field', () {
      final sourceId = LSLStreamInfoHelper.generateSourceID(
        CoordinationStreamConfig(name: 'a//b'),
        node: participant(),
      );
      expect(sourceId, 'a//b//participant//uid-0//Node_0');

      final parsed = LSLStreamInfoHelper.parseSourceId(sourceId);
      expect(parsed[LSLStreamInfoHelper.streamNameKey], 'a');
      expect(
        parsed[LSLStreamInfoHelper.nodeRoleKey],
        'b',
        reason: 'BUG: fields shift left when the stream name contains "//"',
      );
      expect(parsed[LSLStreamInfoHelper.nodeUIdKey], 'participant');
      expect(parsed[LSLStreamInfoHelper.nodeIdKey], 'uid-0');
    });
  });
}
