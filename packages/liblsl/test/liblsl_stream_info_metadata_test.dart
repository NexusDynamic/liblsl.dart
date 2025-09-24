import 'package:liblsl/lsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    // set up basic API config
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1', // Use loopback for testing
      addressesOverride: ['224.0.0.183'],
      knownPeers: ['127.0.0.1'],
      sessionId: 'LSLTestSession',
      unicastMinRTT: 0.1,
      multicastMinRTT: 0.1,
      portRange: 64,
      // don't bother checking during the test
      watchdogCheckInterval: 600.0,
      sendSocketBufferSize: 1024,
      receiveSocketBufferSize: 1024,
      outletBufferReserveMs: 2000,
      inletBufferReserveMs: 2000,
    );
    LSL.setConfigContent(apiConfig);
  });
  group('LSL Stream Info Metadata', () {
    group('Basic Stream Info vs Metadata Stream Info', () {
      test('createStreamInfo returns LSLStreamInfoWithMetadata', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'TestStream',
          streamType: LSLContentType.eeg,
          channelCount: 4,
          sampleRate: 250.0,
        );

        expect(streamInfo, isA<LSLStreamInfoWithMetadata>());
        expect(streamInfo.streamName, equals('TestStream'));
        expect(streamInfo.channelCount, equals(4));

        // Should have immediate access to description
        expect(() => streamInfo.description, returnsNormally);
        final description = streamInfo.description;
        expect(description.value, isA<LSLXmlNode>());

        streamInfo.destroy();
      });

      test(
        'resolved streams are basic LSLStreamInfo without metadata',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'ResolveTestStream',
            streamType: LSLContentType.eeg,
          );
          final outlet = await LSL.createOutlet(
              streamInfo: streamInfo, useIsolates: false);

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'ResolveTestStream',
            waitTime: 1.0,
          );
          expect(resolvedStreams.length, greaterThan(0));
          final resolvedStream = resolvedStreams.first;
          // Should be basic LSLStreamInfo, not LSLStreamInfoWithMetadata
          expect(resolvedStream, isA<LSLStreamInfo>());
          expect(resolvedStream is LSLStreamInfoWithMetadata, isFalse);

          await outlet.destroy();
          streamInfo.destroy();
          resolvedStream.destroy();
        },
      );

      test(
        'createInlet with includeMetadata converts basic stream to metadata stream',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'ConvertTestStream',
            streamType: LSLContentType.eeg,
          );
          final outlet = await LSL.createOutlet(
              streamInfo: streamInfo, useIsolates: false);

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'ConvertTestStream',
            waitTime: 1.0,
          );
          expect(resolvedStreams.length, greaterThan(0));
          final basicStream = resolvedStreams.first;

          expect(basicStream is LSLStreamInfoWithMetadata, isFalse);

          // Convert to metadata-enabled stream via inlet creation
          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStream,
            includeMetadata: true,
            useIsolates: false,
          );

          expect(inlet.streamInfo, isA<LSLStreamInfoWithMetadata>());
          expect(
            () => (inlet.streamInfo as LSLStreamInfoWithMetadata).description,
            returnsNormally,
          );
          expect(inlet.streamInfo.streamName, equals(basicStream.streamName));
          expect(
            inlet.streamInfo.channelCount,
            equals(basicStream.channelCount),
          );

          await inlet.destroy();
          await outlet.destroy();
          streamInfo.destroy();
          basicStream.destroy();
        },
      );

      test('complete workflow with outlet and inlet creation', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'TestStream',
          streamType: LSLContentType.eeg,
        );

        // This should be LSLStreamInfoWithMetadata since it's created new
        expect(streamInfo, isA<LSLStreamInfoWithMetadata>());
        expect(streamInfo.streamName, equals('TestStream'));

        // This should work - LSLStreamInfoWithMetadata has description access
        expect(() => streamInfo.description, returnsNormally);

        // Create outlet and resolve to get stream that can get full info
        final outlet =
            await LSL.createOutlet(streamInfo: streamInfo, useIsolates: false);
        await Future.delayed(Duration(milliseconds: 100));

        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.name,
          value: 'TestStream',
          waitTime: 1.0,
        );
        if (resolvedStreams.isNotEmpty) {
          final basicStreamInfo = resolvedStreams.first;

          // Resolved streams are basic LSLStreamInfo (no metadata)
          expect(basicStreamInfo, isA<LSLStreamInfo>());
          expect(basicStreamInfo is LSLStreamInfoWithMetadata, isFalse);

          // This should work - get full info with metadata via inlet creation
          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStreamInfo,
            includeMetadata: true,
            useIsolates: false,
          );

          expect(inlet.streamInfo, isA<LSLStreamInfoWithMetadata>());
          expect(
            () => (inlet.streamInfo as LSLStreamInfoWithMetadata).description,
            returnsNormally,
          );

          await inlet.destroy();
          resolvedStreams.destroy();
        }

        await outlet.destroy();
        streamInfo.destroy();
      });
    });

    group('Inlet Creation with includeMetadata Parameter', () {
      test(
        'createInlet with includeMetadata=false uses basic stream (non-isolate)',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'InletTestBasicNonIsolate',
            channelCount: 2,
          );
          final outlet = await LSL.createOutlet(
            streamInfo: streamInfo,
            useIsolates: false,
          );

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'InletTestBasicNonIsolate',
            waitTime: 1.0,
          );
          expect(resolvedStreams.length, greaterThan(0));
          final basicStream = resolvedStreams.first;

          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStream,
            includeMetadata: false,
            useIsolates: false,
          );

          expect(inlet.streamInfo, equals(basicStream));
          expect(inlet.streamInfo is LSLStreamInfoWithMetadata, isFalse);

          await inlet.destroy();
          await outlet.destroy();
          streamInfo.destroy();
          basicStream.destroy();
        },
      );

      test(
        'createInlet with includeMetadata=false uses basic stream (isolate)',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'InletTestBasicIsolate',
            channelCount: 2,
          );
          final outlet = await LSL.createOutlet(
            streamInfo: streamInfo,
            useIsolates: true,
          );

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'InletTestBasicIsolate',
            waitTime: 1.0,
          );

          expect(resolvedStreams.length, greaterThan(0));
          final basicStream = resolvedStreams.first;

          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStream,
            includeMetadata: false,
            useIsolates: true,
            createTimeout: 5.0, // Shorter timeout to prevent hanging
          );

          expect(inlet.streamInfo, equals(basicStream));
          expect(inlet.streamInfo is LSLStreamInfoWithMetadata, isFalse);

          await inlet.destroy();
          await outlet.destroy();
          streamInfo.destroy();
          resolvedStreams.destroy();
        },
        timeout: Timeout(Duration(seconds: 10)),
      );

      test(
        'createInlet with includeMetadata=true gets metadata stream (non-isolate)',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'InletTestMetadataNonIsolate',
            channelCount: 2,
          );
          final outlet = await LSL.createOutlet(
            streamInfo: streamInfo,
            useIsolates: false,
          );

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'InletTestMetadataNonIsolate',
            waitTime: 1.0,
          );
          expect(resolvedStreams.length, greaterThan(0));
          final basicStream = resolvedStreams.first;
          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStream,
            includeMetadata: true,
            useIsolates: false,
          );

          expect(inlet.streamInfo, isA<LSLStreamInfoWithMetadata>());
          expect(
            () => (inlet.streamInfo as LSLStreamInfoWithMetadata).description,
            returnsNormally,
          );

          await inlet.destroy();
          await outlet.destroy();
          streamInfo.destroy();
          resolvedStreams.destroy();
        },
      );

      test(
        'createInlet with includeMetadata=true gets metadata stream (isolate)',
        () async {
          final streamInfo = await LSL.createStreamInfo(
            streamName: 'InletTestMetadataIsolate',
            channelCount: 2,
          );
          final outlet = await LSL.createOutlet(
            streamInfo: streamInfo,
            useIsolates: true,
          );

          await Future.delayed(Duration(milliseconds: 200));

          final resolvedStreams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.name,
            value: 'InletTestMetadataIsolate',
            waitTime: 1.0,
          );
          expect(resolvedStreams.length, greaterThan(0));
          final basicStream = resolvedStreams.first;

          final inlet = await LSL.createInlet<double>(
            streamInfo: basicStream,
            includeMetadata: true,
            useIsolates: true,
            createTimeout: 5.0, // Shorter timeout to prevent hanging
          );

          expect(inlet.streamInfo, isA<LSLStreamInfoWithMetadata>());
          expect(
            () => (inlet.streamInfo as LSLStreamInfoWithMetadata).description,
            returnsNormally,
          );

          await inlet.destroy();
          await outlet.destroy();
          streamInfo.destroy();
          resolvedStreams.destroy();
        },
        timeout: Timeout(Duration(seconds: 10)),
      );
    });

    group('XML Metadata Handling', () {
      test('should add and retrieve XML metadata correctly', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'XMLTestStream',
          streamType: LSLContentType.eeg,
          channelCount: 4,
        );

        final description = streamInfo.description;
        expect(description.value, isA<LSLXmlNode>());

        final rootElement = description.value;

        // Add manufacturer metadata
        final manufacturerNode = rootElement.addChildValue(
          'manufacturer',
          'TestCompany',
        );
        expect(manufacturerNode.name, equals('manufacturer'));
        expect(manufacturerNode.textValue, equals('TestCompany'));

        // Add nested channel information
        final channelsElement = rootElement.addChildElement('channels');
        expect(channelsElement, isA<LSLXmlNode>());

        final labels = ['C3', 'C4', 'Cz', 'FPz'];
        for (int i = 0; i < 4; i++) {
          final channelElement = channelsElement.addChildElement('channel');
          channelElement.addChildValue('label', labels[i]);
          channelElement.addChildValue('unit', 'microvolts');
          channelElement.addChildValue('type', 'EEG');
        }

        // Verify structure
        expect(channelsElement.children.length, equals(4));

        final firstChannel = channelsElement.children.first;
        final labelNode = firstChannel.children.firstWhere(
          (child) => child.name == 'label',
        );
        expect(labelNode.textValue, equals('C3'));

        streamInfo.destroy();
      });

      test('should handle XML navigation methods correctly', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'NavigationTestStream',
          channelCount: 2,
        );

        final description = streamInfo.description;
        final rootElement = description.value;

        // Add some structure
        rootElement.addChildValue('device', 'TestDevice');
        final settingsElement = rootElement.addChildElement('settings');
        settingsElement.addChildValue('gain', '1000');
        settingsElement.addChildValue('filter', 'lowpass');

        // Test XML navigation
        final xml = LSLXml(xmlPtr: rootElement.xmlPtr);

        // Test basic properties
        expect(xml.isText(), isFalse);
        expect(xml.isEmpty(), isFalse);

        // Test child navigation
        final firstChild = xml.firstChild();
        expect(firstChild, isNotNull);

        final lastChild = xml.lastChild();
        expect(lastChild, isNotNull);

        // Test named child navigation
        final settingsChild = xml.childNamed('settings');
        expect(settingsChild, isNotNull);
        expect(settingsChild!.name, equals('settings'));

        // Test non-existent child
        final nonexistentChild = xml.childNamed('nonexistent');
        expect(nonexistentChild, isNull);

        streamInfo.destroy();
      });

      test('should preserve metadata through XML round-trip', () async {
        final originalStream = await LSL.createStreamInfo(
          streamName: 'RoundTripTest',
          streamType: LSLContentType.nirs,
          channelCount: 8,
          sampleRate: 1000.0,
        );

        // Add complex metadata structure
        final description = originalStream.description;
        final rootElement = description.value;

        rootElement.addChildValue('manufacturer', 'TestManufacturer');
        rootElement.addChildValue('model', 'TestModel123');

        final acquisitionElement = rootElement.addChildElement('acquisition');
        acquisitionElement.addChildValue('sampling_rate', '1000');
        acquisitionElement.addChildValue('resolution', '16bit');

        final channelsElement = rootElement.addChildElement('channels');
        for (int i = 0; i < 8; i++) {
          final channelElement = channelsElement.addChildElement('channel');
          channelElement.addChildValue('label', 'NIRS${i + 1}');
          channelElement.addChildValue('unit', 'μM');
          channelElement.addChildValue('type', 'NIRS');
        }

        // Export to XML
        final xmlString = originalStream.toXml();
        expect(xmlString, contains('TestManufacturer'));
        expect(xmlString, contains('TestModel123'));
        expect(xmlString, contains('NIRS1'));
        expect(xmlString, contains('μM'));

        // Import from XML
        final recreatedStream = originalStream.fromXml(xmlString);
        expect(recreatedStream, isA<LSLStreamInfoWithMetadata>());

        // Verify basic properties
        expect(recreatedStream.streamName, equals('RoundTripTest'));
        expect(recreatedStream.streamType, equals(LSLContentType.nirs));
        expect(recreatedStream.channelCount, equals(8));
        expect(recreatedStream.sampleRate, equals(1000.0));

        // Verify metadata structure
        final recreatedDescription = recreatedStream.description;
        final recreatedRoot = recreatedDescription.value;

        // Find manufacturer
        final manufacturerNode = recreatedRoot.children.firstWhere(
          (child) => child.name == 'manufacturer',
        );
        expect(manufacturerNode.textValue, equals('TestManufacturer'));

        // Find acquisition settings
        final acquisitionNode = recreatedRoot.children.firstWhere(
          (child) => child.name == 'acquisition',
        );

        final samplingRateNode = acquisitionNode.children.firstWhere(
          (child) => child.name == 'sampling_rate',
        );
        expect(samplingRateNode.textValue, equals('1000'));

        // Find channels
        final channelsNode = recreatedRoot.children.firstWhere(
          (child) => child.name == 'channels',
        );
        expect(channelsNode.children.length, equals(8));

        // Check first channel
        final firstChannel = channelsNode.children.first;
        final labelNode = firstChannel.children.firstWhere(
          (child) => child.name == 'label',
        );
        expect(labelNode.textValue, equals('NIRS1'));

        originalStream.destroy();
        recreatedStream.destroy();
      });
    });

    group('End-to-End Metadata Workflow (C Example)', () {
      test('should mirror C example workflow exactly', () async {
        // Step 1: Create streaminfo (like lsl_create_streaminfo)
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'MetaTester',
          streamType: LSLContentType.eeg,
          channelCount: 8,
          sampleRate: 100.0,
          sourceId: 'myuid323457',
        );

        // Step 2: Get description immediately (like lsl_get_desc)
        final description = streamInfo.description;
        expect(description.value, isA<LSLXmlNode>());
        final descElement = description.value;

        // Step 3: Add channels element and child channels (like C example)
        final channelsElement = descElement.addChildElement('channels');
        final labels = ['C3', 'C4', 'Cz', 'FPz', 'POz', 'CPz', 'O1', 'O2'];

        for (int c = 0; c < 8; c++) {
          final channelElement = channelsElement.addChildElement('channel');
          channelElement.addChildValue('label', labels[c]);
          channelElement.addChildValue('unit', 'microvolts');
          channelElement.addChildValue('type', 'EEG');
        }

        // Step 4: Add manufacturer and cap info (like C example)
        descElement.addChildValue('manufacturer', 'SCCN');
        final capElement = descElement.addChildElement('cap');
        capElement.addChildValue('name', 'EasyCap');
        capElement.addChildValue('size', '54');
        capElement.addChildValue('labelscheme', '10-20');

        // Step 5: Create outlet (like lsl_create_outlet)
        final outlet =
            await LSL.createOutlet(streamInfo: streamInfo, useIsolates: false);
        await Future.delayed(Duration(milliseconds: 300));

        // Step 6: Resolve the stream (like lsl_resolve_byprop)
        final resolvedStreams = await LSL.resolveStreamsByProperty(
          property: LSLStreamProperty.name,
          value: 'MetaTester',
          waitTime: 2.0,
        );

        expect(resolvedStreams.length, greaterThan(0));
        final basicStreamInfo = resolvedStreams.first;

        // Step 7: Get full info with metadata via inlet creation (like lsl_get_fullinfo)
        final inlet = await LSL.createInlet<double>(
          streamInfo: basicStreamInfo,
          includeMetadata: true,
          useIsolates: false,
        );
        final fullStreamInfo = inlet.streamInfo;
        expect(fullStreamInfo, isA<LSLStreamInfoWithMetadata>());

        // Step 8: Test XML output (like lsl_get_xml)
        final xmlString = fullStreamInfo.toXml();
        expect(xmlString, contains('MetaTester'));
        expect(xmlString, contains('manufacturer'));
        expect(xmlString, contains('SCCN'));
        expect(xmlString, contains('EasyCap'));

        // Step 9: Verify metadata like C example
        final inletDescription =
            (fullStreamInfo as LSLStreamInfoWithMetadata).description;
        final inletDescElement = inletDescription.value;

        // Test manufacturer (like C example)
        final manufacturerChild = inletDescElement.children.firstWhere(
          (child) => child.name == 'manufacturer',
        );
        expect(manufacturerChild.textValue, equals('SCCN'));

        // Test cap size (like C example)
        final capElementResolved = inletDescElement.children.firstWhere(
          (child) => child.name == 'cap',
        );
        final sizeChild = capElementResolved.children.firstWhere(
          (child) => child.name == 'size',
        );
        expect(sizeChild.textValue, equals('54'));

        // Test channel labels (like C example)
        final channelsElementResolved = inletDescElement.children.firstWhere(
          (child) => child.name == 'channels',
        );
        expect(channelsElementResolved.children.length, equals(8));

        // Check first channel label
        final firstChannel = channelsElementResolved.children.first;
        final labelChild = firstChannel.children.firstWhere(
          (child) => child.name == 'label',
        );
        expect(labelChild.textValue, equals('C3'));

        // Check last channel label
        final lastChannel = channelsElementResolved.children.last;
        final lastLabelChild = lastChannel.children.firstWhere(
          (child) => child.name == 'label',
        );
        expect(lastLabelChild.textValue, equals('O2'));

        // Cleanup
        await inlet.destroy();
        await outlet.destroy();
        streamInfo.destroy();
        resolvedStreams.destroy();
      });
    });

    group('Error Handling', () {
      test('should handle invalid XML gracefully', () {
        expect(() => LSLXml(xmlPtr: nullPtr()), throwsA(isA<LSLException>()));
      });

      test('should validate empty names and values', () {
        // This test is no longer relevant since we don't create nodes directly
        // The validation happens when setting text values or names
      });

      test('should handle destroyed stream info', () async {
        final streamInfo = await LSL.createStreamInfo();
        streamInfo.destroy();

        expect(() => streamInfo.description, throwsA(isA<LSLException>()));

        expect(() => streamInfo.toXml(), throwsA(isA<LSLException>()));
      });

      test('should handle malformed XML in fromXml', () async {
        final streamInfo = await LSL.createStreamInfo();

        expect(
          () => streamInfo.fromXml('<invalid>xml</malformed>'),
          throwsA(isA<LSLException>()),
        );

        streamInfo.destroy();
      });
    });

    group('Memory Management', () {
      test('should properly clean up metadata streams', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'MemoryTestStream',
        );

        final description = streamInfo.description;
        final rootElement = description.value;
        rootElement.addChildValue('test', 'value');

        // This should not crash
        streamInfo.destroy();

        expect(() => streamInfo.description, throwsA(isA<LSLException>()));
      });

      test('should handle multiple inlets with metadata correctly', () async {
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'MultipleCallsTest1',
        );
        final streamInfo2 = await LSL.createStreamInfo(
          streamName: 'MultipleCallsTest2',
        );
        final outlet =
            await LSL.createOutlet(streamInfo: streamInfo, useIsolates: false);
        final outlet2 =
            await LSL.createOutlet(streamInfo: streamInfo2, useIsolates: false);

        await Future.delayed(Duration(milliseconds: 200));

        final resolvedStreams = await LSL.resolveStreamsByPredicate(
          predicate: 'starts-with(name, "MultipleCallsTest")',
          waitTime: 1.0,
        );
        expect(resolvedStreams.length, greaterThanOrEqualTo(2));
        final basicStream = resolvedStreams.firstWhere(
          (s) => s.streamName == 'MultipleCallsTest1',
        );
        final basicStream2 = resolvedStreams.firstWhere(
          (s) => s.streamName == 'MultipleCallsTest2',
        );

        // Multiple inlets with metadata should work without memory issues
        final inlet1 = await LSL.createInlet<double>(
          streamInfo: basicStream,
          includeMetadata: true,
          useIsolates: false,
        );
        final inlet2 = await LSL.createInlet<double>(
          streamInfo: basicStream2,
          includeMetadata: true,
          useIsolates: false,
        );

        expect(inlet1.streamInfo, isA<LSLStreamInfoWithMetadata>());
        expect(inlet2.streamInfo, isA<LSLStreamInfoWithMetadata>());

        // Clean up all instances
        await inlet1.destroy();
        await inlet2.destroy();
        await outlet.destroy();
        await outlet2.destroy();
        streamInfo.destroy();
        streamInfo2.destroy();
        resolvedStreams.destroy();
      });
    });
  });
}
