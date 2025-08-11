import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    // Set up basic API config
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
    );
    LSL.setConfigContent(apiConfig);
  });

  group('LSL Stream Resolution', () {
    group('Basic Stream Resolution', () {
      test('should resolve streams with basic resolveStreams method', () async {
        // Create test streams
        final streamInfo1 = await LSL.createStreamInfo(
          streamName: 'BasicResolverTest1',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 250.0,
          sourceId: 'test1',
        );
        final streamInfo2 = await LSL.createStreamInfo(
          streamName: 'BasicResolverTest2',
          streamType: LSLContentType.custom('EMG'),
          channelCount: 4,
          sampleRate: 1000.0,
          sourceId: 'test2',
        );

        final outlet1 = await LSL.createOutlet(
          streamInfo: streamInfo1,
          useIsolates: false,
        );
        final outlet2 = await LSL.createOutlet(
          streamInfo: streamInfo2,
          useIsolates: false,
        );

        // Wait for outlets to be discoverable
        await Future.delayed(Duration(milliseconds: 300));

        // Test basic resolution
        final resolvedStreams = await LSL.resolveStreams(waitTime: 2.0);

        expect(resolvedStreams.length, greaterThanOrEqualTo(2));

        final testStreams = resolvedStreams
            .where((s) => s.streamName.startsWith('BasicResolverTest'))
            .toList();
        expect(testStreams.length, equals(2));

        // Verify stream properties
        final stream1 = testStreams.firstWhere(
          (s) => s.streamName == 'BasicResolverTest1',
        );
        expect(stream1.streamType, equals(LSLContentType.eeg));
        expect(stream1.channelCount, equals(8));
        expect(stream1.sampleRate, equals(250.0));
        expect(stream1.sourceId, equals('test1'));

        final stream2 = testStreams.firstWhere(
          (s) => s.streamName == 'BasicResolverTest2',
        );
        expect(stream2.streamType, equals(LSLContentType.custom('EMG')));
        expect(stream2.channelCount, equals(4));
        expect(stream2.sampleRate, equals(1000.0));
        expect(stream2.sourceId, equals('test2'));

        // Cleanup
        outlet1.destroy();
        outlet2.destroy();
        streamInfo1.destroy();
        streamInfo2.destroy();
        for (final stream in testStreams) {
          stream.destroy();
        }
      });

      test('should handle empty resolution results', () async {
        final resolvedStreams = await LSL.resolveStreams(waitTime: 0.5);
        // Should return empty list or existing streams, but not crash
        expect(resolvedStreams, isA<List<LSLStreamInfo>>());
      });
    });

    group('Property-based Resolution', () {
      late LSLStreamInfo testStream;
      late LSLOutlet testOutlet;

      setUp(() async {
        testStream = await LSL.createStreamInfo(
          streamName: 'PropertyTestStream',
          streamType: LSLContentType.nirs,
          channelCount: 16,
          sampleRate: 500.0,
          sourceId: 'property_test_123',
        );
        testOutlet = await LSL.createOutlet(
          streamInfo: testStream,
          useIsolates: false,
        );
        await Future.delayed(Duration(milliseconds: 300));
      });

      tearDown(() {
        testOutlet.destroy();
        testStream.destroy();
      });

      test('should resolve by stream name', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.name,
          value: 'PropertyTestStream',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, equals(1));
        expect(resolvedStreams.first.streamName, equals('PropertyTestStream'));

        resolvedStreams.first.destroy();
      });

      test('should resolve by stream type', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.type,
          value: 'NIRS',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final testStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'PropertyTestStream',
        );
        expect(testStream.streamType, equals(LSLContentType.nirs));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve by channel count', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.channelCount,
          value: '16',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final testStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'PropertyTestStream',
        );
        expect(testStream.channelCount, equals(16));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve by channel format', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.channelFormat,
          value: 'float32',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final testStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'PropertyTestStream',
        );
        expect(testStream.channelFormat, equals(LSLChannelFormat.float32));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve by source ID', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.sourceId,
          value: 'property_test_123',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, equals(1));
        expect(resolvedStreams.first.streamName, equals('PropertyTestStream'));
        expect(resolvedStreams.first.sourceId, equals('property_test_123'));

        resolvedStreams.first.destroy();
      });

      test('should resolve by sample rate', () async {
        // the sample rate in the XML is a string, so we need to pass it as such
        // and it should match the string representation of the sample rate
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.sampleRate,
          value: '500.0000000000000',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final testStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'PropertyTestStream',
        );
        expect(testStream.sampleRate, equals(500.0));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should handle non-matching property values', () async {
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.name,
          value: 'NonExistentStream',
          waitTime: 1.0,
        );

        expect(resolvedStreams.length, equals(0));
      });
    });

    group('Predicate-based Resolution', () {
      late List<LSLStreamInfo> testStreams;
      late List<LSLOutlet> testOutlets;

      setUp(() async {
        testStreams = [];
        testOutlets = [];

        // Create diverse test streams for predicate testing
        final stream1 = await LSL.createStreamInfo(
          streamName: 'BioSemi_EEG_32',
          streamType: LSLContentType.eeg,
          channelCount: 32,
          sampleRate: 1000.0,
          sourceId: 'biosemi_001',
        );
        testStreams.add(stream1);

        final stream2 = await LSL.createStreamInfo(
          streamName: 'BioSemi_EMG_8',
          streamType: LSLContentType.custom('EMG'),
          channelCount: 8,
          sampleRate: 2000.0,
          sourceId: 'biosemi_002',
        );
        testStreams.add(stream2);

        final stream3 = await LSL.createStreamInfo(
          streamName: 'Neuroscan_EEG_64',
          streamType: LSLContentType.eeg,
          channelCount: 64,
          sampleRate: 500.0,
          sourceId: 'neuroscan_001',
        );
        testStreams.add(stream3);

        // Add metadata to first stream for testing desc predicates
        final description = stream1.description;
        final rootElement = description.value;
        rootElement.addChildValue('manufacturer', 'BioSemi');
        rootElement.addChildValue('model', 'ActiveTwo');
        final channelsElement = rootElement.addChildElement('channels');
        for (int i = 0; i < 32; i++) {
          final channelElement = channelsElement.addChildElement('channel');
          channelElement.addChildValue('label', 'CH${i + 1}');
          channelElement.addChildValue('unit', 'microvolts');
          channelElement.addChildValue('type', 'EEG');
        }

        // Create outlets
        for (final stream in testStreams) {
          final outlet = await LSL.createOutlet(
            streamInfo: stream,
            useIsolates: false,
          );
          testOutlets.add(outlet);
        }

        await Future.delayed(Duration(milliseconds: 500));
      });

      tearDown(() {
        for (final outlet in testOutlets) {
          outlet.destroy();
        }
        for (final stream in testStreams) {
          stream.destroy();
        }
      });

      test('should resolve by simple name predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "name='BioSemi_EEG_32'",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, equals(1));
        expect(resolvedStreams.first.streamName, equals('BioSemi_EEG_32'));
        expect(resolvedStreams.first.streamType, equals(LSLContentType.eeg));

        resolvedStreams.first.destroy();
      });

      test('should resolve by type predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "type='EEG'",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(2));
        final testEEGStreams = resolvedStreams
            .where(
              (s) =>
                  s.streamName.contains('BioSemi_EEG_32') ||
                  s.streamName.contains('Neuroscan_EEG_64'),
            )
            .toList();
        expect(testEEGStreams.length, equals(2));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using starts-with predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "starts-with(name, 'BioSemi')",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(2));
        final bioSemiStreams = resolvedStreams
            .where((s) => s.streamName.startsWith('BioSemi'))
            .toList();
        expect(bioSemiStreams.length, equals(2));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using combined AND predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "type='EEG' and starts-with(name, 'BioSemi')",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final targetStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'BioSemi_EEG_32',
        );
        expect(targetStream.streamType, equals(LSLContentType.eeg));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using combined OR predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "name='BioSemi_EEG_32' or name='Neuroscan_EEG_64'",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(2));
        final testStreamsFound = resolvedStreams
            .where(
              (s) =>
                  s.streamName == 'BioSemi_EEG_32' ||
                  s.streamName == 'Neuroscan_EEG_64',
            )
            .toList();
        expect(testStreamsFound.length, equals(2));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using channel count predicate', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "channel_count=32",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final targetStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'BioSemi_EEG_32',
        );
        expect(targetStream.channelCount, equals(32));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using sample rate comparison', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "nominal_srate>=1000",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(2));
        final highSampleRateStreams = resolvedStreams
            .where(
              (s) =>
                  s.streamName.contains('BioSemi_EEG_32') ||
                  s.streamName.contains('BioSemi_EMG_8'),
            )
            .toList();
        expect(highSampleRateStreams.length, equals(2));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should resolve using complex metadata predicate', () async {
        // This tests resolving streams with metadata in description
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate:
              "type='EEG' and starts-with(name, 'BioSemi') and count(//info/desc/channels/channel)=32",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final targetStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'BioSemi_EEG_32',
        );
        expect(targetStream.channelCount, equals(32));
        expect(targetStream.streamType, equals(LSLContentType.eeg));

        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should handle invalid predicate gracefully', () async {
        // Test with malformed predicate
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "invalid_syntax_here",
          waitTime: 1.0,
        );
        expect(resolvedStreams.length, equals(0));
      });

      test('should handle predicate that matches no streams', () async {
        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: "name='NonExistentStream' and type='NonExistentType'",
          waitTime: 1.0,
        );

        expect(resolvedStreams.length, equals(0));
      });
    });

    group('Continuous Stream Resolution', () {
      test('should create and use continuous resolver', () async {
        final continuousResolver = LSL.createContinuousStreamResolver(
          forgetAfter: 5.0,
          maxStreams: 10,
        );

        // Create a test stream
        final testStream = await LSL.createStreamInfo(
          streamName: 'ContinuousResolverTest',
          streamType: LSLContentType.audio,
          channelCount: 2,
        );
        final testOutlet = await LSL.createOutlet(
          streamInfo: testStream,
          useIsolates: false,
        );

        // Wait for stream to be discoverable
        await Future.delayed(Duration(milliseconds: 500));

        // Resolve using continuous resolver
        final resolvedStreams = await continuousResolver.resolve(waitTime: 2.0);

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final targetStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'ContinuousResolverTest',
          orElse: () => throw StateError('Test stream not found'),
        );
        expect(targetStream.streamType, equals(LSLContentType.audio));
        expect(targetStream.channelCount, equals(2));

        // Cleanup
        testOutlet.destroy();
        testStream.destroy();
        continuousResolver.destroy();
        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });

      test('should handle continuous resolver with property filter', () async {
        final continuousResolver = LSL.createContinuousStreamResolver(
          forgetAfter: 3.0,
          maxStreams: 5,
        );

        // Create multiple test streams
        final testStream1 = await LSL.createStreamInfo(
          streamName: 'ContinuousTest1',
          streamType: LSLContentType.mocap,
          channelCount: 6,
        );
        final testStream2 = await LSL.createStreamInfo(
          streamName: 'ContinuousTest2',
          streamType: LSLContentType.mocap,
          channelCount: 12,
        );

        final testOutlet1 = await LSL.createOutlet(
          streamInfo: testStream1,
          useIsolates: false,
        );
        final testOutlet2 = await LSL.createOutlet(
          streamInfo: testStream2,
          useIsolates: false,
        );

        await Future.delayed(Duration(milliseconds: 500));

        // Test resolving by property
        final mocapStreams = await continuousResolver.resolveByProperty(
          property: LSLStreamProperty.type,
          value: 'MoCap',
          waitTime: 2.0,
        );

        expect(mocapStreams.length, greaterThanOrEqualTo(2));
        final testStreamsFound = mocapStreams
            .where((s) => s.streamName.startsWith('ContinuousTest'))
            .toList();
        expect(testStreamsFound.length, equals(2));

        // Cleanup
        testOutlet1.destroy();
        testOutlet2.destroy();
        testStream1.destroy();
        testStream2.destroy();
        continuousResolver.destroy();
        for (final stream in mocapStreams) {
          stream.destroy();
        }
      });

      test('should handle continuous resolver with predicate', () async {
        final continuousResolver = LSL.createContinuousStreamResolver();

        // Create test stream
        final testStream = await LSL.createStreamInfo(
          streamName: 'PredicateTestStream',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 256.0,
        );
        final testOutlet = await LSL.createOutlet(
          streamInfo: testStream,
          useIsolates: false,
        );

        await Future.delayed(Duration(milliseconds: 500));

        // Test predicate resolution
        final resolvedStreams = await continuousResolver.resolveByPredicate(
          predicate: "starts-with(name, 'PredicateTest') and channel_count=8",
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThanOrEqualTo(1));
        final targetStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'PredicateTestStream',
        );
        expect(targetStream.channelCount, equals(8));
        expect(targetStream.sampleRate, equals(256.0));

        // Cleanup
        testOutlet.destroy();
        testStream.destroy();
        continuousResolver.destroy();
        for (final stream in resolvedStreams) {
          stream.destroy();
        }
      });
    });

    group('Resolution Error Handling', () {
      test('should handle resolution timeout gracefully', () async {
        // Test very short timeout
        final resolvedStreams = await LSL.resolveStreams(waitTime: 0.001);
        expect(resolvedStreams, isA<List<LSLStreamInfo>>());
      });

      test('should handle property resolution with invalid property', () async {
        // This should work but return no results for unknown property values
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.name,
          value: 'NonExistentStream_12345',
          waitTime: 0.5,
        );
        expect(resolvedStreams.length, equals(0));
      });

      test('should validate minimum stream count parameter', () async {
        // Test with minStreamCount
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.type,
          value: 'EEG',
          waitTime: 1.0,
          minStreamCount: 0, // Should work with 0
        );
        expect(resolvedStreams, isA<List<LSLStreamInfo>>());
      });

      test('should handle max streams limitation', () async {
        final resolvedStreams = await LSL.resolveStreams(
          waitTime: 1.0,
          maxStreams: 1, // Limit to 1 stream
        );
        expect(resolvedStreams.length, lessThanOrEqualTo(1));
      });
    });
  });
}
