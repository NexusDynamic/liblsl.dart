import 'dart:async';
import 'package:test/test.dart';
import 'package:liblsl/lsl.dart';
import 'package:liblsl_coordinator/src/coordination/lsl/high_frequency_transport.dart';
import 'package:liblsl_coordinator/src/coordination/core/coordination_message.dart';
import 'package:liblsl_coordinator/src/coordination/lsl/lsl_transport.dart';

void main() {
  group('HighFrequencyLSLTransport Tests', () {
    late HighFrequencyLSLTransport transport;

    setUp(() {
      transport = HighFrequencyLSLTransport(
        streamName: 'test_stream',
        nodeId: 'test_node',
        sampleRate: 100.0,
        performanceConfig: const HighFrequencyConfig(
          targetFrequency: 100.0,
          useBusyWait: false, // Use timer-based for testing
          bufferSize: 10,
          useIsolate: false, // Start with non-isolate mode for unit tests
          channelCount: 2, // Support both single events and event+value pairs
        ),
        lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
      );
    });

    tearDown(() async {
      await transport.dispose();
    });

    group('Configuration Tests', () {
      test('should initialize with correct default configuration', () {
        expect(transport.streamName, equals('test_stream'));
        expect(transport.nodeId, equals('test_node'));
        expect(transport.sampleRate, equals(100.0));
      });

      test('should create with custom configuration', () {
        final customConfig = HighFrequencyConfig(
          targetFrequency: 500.0,
          useBusyWait: true,
          bufferSize: 50,
          useIsolate: true,
          channelFormat: LSLChannelFormat.float32,
          channelCount: 4,
        );

        final customTransport = HighFrequencyLSLTransport(
          streamName: 'custom_stream',
          nodeId: 'custom_node',
          performanceConfig: customConfig,
          lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
        );

        expect(customTransport.performanceMetrics.actualFrequency, equals(0.0));
        expect(customTransport.streamName, equals('custom_stream'));
        expect(customTransport.nodeId, equals('custom_node'));

        customTransport.dispose();
      });

      test('should calculate correct target interval microseconds', () {
        const config = HighFrequencyConfig(targetFrequency: 1000.0);
        expect(config.targetIntervalMicroseconds, equals(1000));

        const config500 = HighFrequencyConfig(targetFrequency: 500.0);
        expect(config500.targetIntervalMicroseconds, equals(2000));
      });
    });

    group('Data Sending Tests', () {
      test('should send single-channel int event', () async {
        // Initialize transport first
        await transport.initialize();

        // Note: This test will use fallback coordination message mode
        // since we're not using isolates in test mode
        await transport.sendEvent(42);

        // Verify the transport is still responsive
        expect(transport.nodeId, equals('test_node'));
      });

      test('should send two-channel int data', () async {
        await transport.initialize();

        await transport.sendEventWithValue(100, 200);

        // Verify the transport is still responsive
        expect(transport.nodeId, equals('test_node'));
      });

      test('should send multi-channel double data', () async {
        await transport.initialize();

        await transport.sendPositionData([1.0, 2.0, 3.0]);

        // Verify the transport is still responsive
        expect(transport.nodeId, equals('test_node'));
      });

      test('should send generic typed data', () async {
        await transport.initialize();

        await transport.sendGameData([1, 2, 3, 4, 5]);
        await transport.sendGameData([1.1, 2.2, 3.3]);
        await transport.sendGameData(['a', 'b', 'c']);

        // Verify the transport is still responsive
        expect(transport.nodeId, equals('test_node'));
      });
    });

    group('Stream Tests', () {
      test('should provide game data stream', () {
        expect(transport.gameDataStream, isA<Stream<GameDataSample>>());
      });

      test('should provide backward compatibility message stream', () {
        expect(
          transport.highPerformanceMessageStream,
          isA<Stream<CoordinationMessage>>(),
        );
      });

      test('should handle stream subscription and cancellation', () async {
        final subscription = transport.gameDataStream.listen((sample) {
          // Handle samples
        });

        await Future.delayed(const Duration(milliseconds: 10));
        await subscription.cancel();
      });
    });

    group('Performance Metrics Tests', () {
      test('should start with empty metrics', () {
        final metrics = transport.performanceMetrics;
        expect(metrics.actualFrequency, equals(0.0));
        expect(metrics.samplesProcessed, equals(0));
        expect(metrics.droppedSamples, equals(0));
        expect(metrics.timeCorrections, isEmpty);
      });

      test('should serialize and deserialize metrics', () {
        final originalMetrics = HighFrequencyMetrics(
          actualFrequency: 100.0,
          samplesProcessed: 50,
          droppedSamples: 2,
          timeCorrections: {'device1': 0.001, 'device2': -0.002},
          timestamp: DateTime.now(),
        );

        final map = originalMetrics.toMap();
        final deserializedMetrics = HighFrequencyMetrics.fromMap(map);

        expect(deserializedMetrics.actualFrequency, equals(100.0));
        expect(deserializedMetrics.samplesProcessed, equals(50));
        expect(deserializedMetrics.droppedSamples, equals(2));
        expect(
          deserializedMetrics.timeCorrections['device1'],
          closeTo(0.001, 0.0001),
        );
        expect(
          deserializedMetrics.timeCorrections['device2'],
          closeTo(-0.002, 0.0001),
        );
      });
    });

    group('Game Data Sample Tests', () {
      test('should create and serialize game data sample', () {
        final sample = GameDataSample(
          sourceId: 'test_source',
          channelData: [1, 2, 3],
          timestamp: 1000000,
          timeCorrection: 0.001,
          channelFormat: LSLChannelFormat.int32,
        );

        expect(sample.sourceId, equals('test_source'));
        expect(sample.channelData, equals([1, 2, 3]));
        expect(sample.timestamp, equals(1000000));
        expect(sample.timeCorrection, equals(0.001));
        expect(sample.channelFormat, equals(LSLChannelFormat.int32));
      });

      test('should deserialize game data sample from map', () {
        final map = {
          'source_id': 'test_source',
          'channel_data': [1, 2, 3],
          'timestamp': 1000000,
          'time_correction': 0.001,
          'channel_format': LSLChannelFormat.int32.index,
        };

        final sample = GameDataSample.fromMap(map);
        expect(sample.sourceId, equals('test_source'));
        expect(sample.channelData, equals([1, 2, 3]));
        expect(sample.timestamp, equals(1000000));
        expect(sample.timeCorrection, equals(0.001));
        expect(sample.channelFormat, equals(LSLChannelFormat.int32));
      });

      test('should extract single-channel event code', () {
        final sample = GameDataSample(
          sourceId: 'test',
          channelData: [42],
          timestamp: 1000000,
          channelFormat: LSLChannelFormat.int32,
        );

        expect(sample.eventCode, equals(42));
      });

      test('should extract two-channel event with value', () {
        final sample = GameDataSample(
          sourceId: 'test',
          channelData: [100, 200],
          timestamp: 1000000,
          channelFormat: LSLChannelFormat.int32,
        );

        final (event, value) = sample.eventWithValue;
        expect(event, equals(100));
        expect(value, equals(200));
      });

      test('should extract position data as doubles', () {
        final sample = GameDataSample(
          sourceId: 'test',
          channelData: [1.1, 2.2, 3.3],
          timestamp: 1000000,
          channelFormat: LSLChannelFormat.float32,
        );

        final positions = sample.positionData;
        expect(positions, hasLength(3));
        expect(positions[0], closeTo(1.1, 0.01));
        expect(positions[1], closeTo(2.2, 0.01));
        expect(positions[2], closeTo(3.3, 0.01));
      });

      test('should handle empty channel data gracefully', () {
        final sample = GameDataSample(
          sourceId: 'test',
          channelData: [],
          timestamp: 1000000,
          channelFormat: LSLChannelFormat.int32,
        );

        expect(sample.eventCode, equals(0));
        final (event, value) = sample.eventWithValue;
        expect(event, equals(0));
        expect(value, equals(0));
        expect(sample.positionData, isEmpty);
      });
    });

    group('Time Correction Tests', () {
      test('should create time correction info', () {
        final correction = TimeCorrectionInfo(
          sourceId: 'test_source',
          correctionSeconds: 0.001,
          timestamp: DateTime.now(),
        );

        expect(correction.sourceId, equals('test_source'));
        expect(correction.correctionSeconds, equals(0.001));
        expect(correction.timestamp, isA<DateTime>());
      });

      test('should serialize and deserialize time correction', () {
        final originalCorrection = TimeCorrectionInfo(
          sourceId: 'test_source',
          correctionSeconds: 0.001,
          timestamp: DateTime.now(),
        );

        final map = originalCorrection.toMap();
        final deserializedCorrection = TimeCorrectionInfo.fromMap(map);

        expect(deserializedCorrection.sourceId, equals('test_source'));
        expect(
          deserializedCorrection.correctionSeconds,
          closeTo(0.001, 0.0001),
        );
        expect(
          deserializedCorrection.timestamp.microsecondsSinceEpoch,
          equals(originalCorrection.timestamp.microsecondsSinceEpoch),
        );
      });
    });

    group('Lifecycle Tests', () {
      test('should initialize and dispose cleanly', () async {
        final testTransport = HighFrequencyLSLTransport(
          streamName: 'lifecycle_test',
          nodeId: 'lifecycle_node',
          performanceConfig: const HighFrequencyConfig(useIsolate: false),
          lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
        );

        await testTransport.initialize();
        expect(testTransport.nodeId, equals('lifecycle_node'));

        await testTransport.dispose();
        // Should not throw after disposal
      });

      test('should handle multiple dispose calls', () async {
        final testTransport = HighFrequencyLSLTransport(
          streamName: 'multi_dispose_test',
          nodeId: 'multi_dispose_node',
          performanceConfig: const HighFrequencyConfig(useIsolate: false),
          lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
        );

        await testTransport.initialize();
        await testTransport.dispose();
        await testTransport.dispose(); // Should not throw
      });
    });

    group('Error Handling Tests', () {
      test('should handle invalid configuration gracefully', () {
        // Test that invalid frequency throws an error
        expect(
          () => HighFrequencyConfig(targetFrequency: -1.0),
          throwsA(anything),
        );
      });

      test('should handle sending data before initialization', () async {
        final testTransport = HighFrequencyLSLTransport(
          streamName: 'uninit_test',
          nodeId: 'uninit_node',
          performanceConfig: const HighFrequencyConfig(useIsolate: false),
          lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
        );

        // Should throw LSLTransportException when not initialized
        expect(
          () async => await testTransport.sendEvent(42),
          throwsA(isA<LSLTransportException>()),
        );

        await testTransport.dispose();
      });
    });
  });
}
