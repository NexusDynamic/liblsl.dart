import 'dart:async';
import 'package:liblsl/lsl.dart';

void main() async {
  // Example 1: Basic outlet and inlet in a single application
  await basicExample();

  // Example 2: Advanced usage with multiple streams
  await multiStreamExample();
}

/// Basic example showing how to create an outlet and inlet
Future<void> basicExample() async {
  print('\n=== Basic LSL Example ===');

  // Create the main LSL instance with isolates enabled
  print('LSL Library Version: ${LSL.version}');

  // print library info
  final libraryInfo = LSL.libraryInfo();
  print('LSL Library Info: $libraryInfo');

  try {
    // Create stream info for EEG data
    final streamInfo = await LSL.createStreamInfo(
      streamName: 'MyEEGStream',
      streamType: LSLContentType.eeg,
      channelCount: 8,
      sampleRate: 250.0,
      channelFormat: LSLChannelFormat.float32,
      sourceId: 'MyEEGDevice',
    );
    print('Created stream info: $streamInfo');

    // Create an outlet
    print('creating outlet...');
    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 0,
      maxBuffer: 360,
    );
    print('Created outlet: $outlet');

    // Start sending data in the background
    final senderCompleter = Completer<void>();
    final senderFuture = _sampleSender(outlet, senderCompleter);

    // Allow time for the outlet to start broadcasting
    await Future.delayed(Duration(milliseconds: 500));

    // Resolve available streams
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 5);
    print('Found ${streams.length} streams:');

    for (final stream in streams) {
      print('  - ${stream.toString()}');
    }

    // Find our EEG stream
    final eegStream = streams.firstWhere(
      (s) => s.streamName == 'MyEEGStream',
      orElse: () => throw LSLException('EEG stream not found'),
    );

    // Create an inlet for the EEG stream
    final inlet = await LSL.createInlet<double>(
      streamInfo: eegStream,
      maxBufferSize: 360,
      maxChunkLength: 0,
      recover: true,
    );
    print('Created inlet: $inlet');

    // Receive some samples
    print('Receiving samples:');
    for (int i = 0; i < 5; i++) {
      final sample = await inlet.pullSample(timeout: 5.0);
      print('  Sample $i: ${sample.data}, timestamp: ${sample.timestamp}');
      await Future.delayed(Duration(milliseconds: 100));
    }

    // Stop sending samples
    senderCompleter.complete();
    await senderFuture;

    // Clean up
    inlet.destroy();
    outlet.destroy();
    streamInfo.destroy();
    print('Resources cleaned up');
  } catch (e) {
    print('Error: $e');
    // Clean up in case of error
  }
}

/// Advanced example with multiple streams
Future<void> multiStreamExample() async {
  print('\n=== Multi-Stream LSL Example ===');

  try {
    // Create EEG stream info
    final eegInfo = await LSL.createStreamInfo(
      streamName: 'EEGData',
      streamType: LSLContentType.eeg,
      channelCount: 4,
      sampleRate: 100.0,
      channelFormat: LSLChannelFormat.float32,
      sourceId: 'EEGDevice1',
    );

    // Create marker stream info
    final markerInfo = await LSL.createStreamInfo(
      streamName: 'MarkerStream',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE, // Irregular rate for event markers
      channelFormat: LSLChannelFormat.string,
      sourceId: 'MarkerDevice1',
    );

    // Create outlets
    final eegOutlet = await LSL.createOutlet(
      streamInfo: eegInfo,
      chunkSize: 0,
      maxBuffer: 360,
    );
    final markerOutlet = await LSL.createOutlet(
      streamInfo: markerInfo,
      chunkSize: 0,
      maxBuffer: 360,
    );

    print('Created EEG and Marker outlets');

    // Start sending data
    final eegCompleter = Completer<void>();
    final markerCompleter = Completer<void>();

    final eegSenderFuture = _sampleSender(eegOutlet, eegCompleter);
    final markerSenderFuture = _markerSender(markerOutlet, markerCompleter);

    // Allow time for the outlets to start
    await Future.delayed(Duration(milliseconds: 500));

    // Resolve all streams
    final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 10);

    print('Found ${streams.length} streams');

    // Find our streams
    final foundEegStream = streams.firstWhere(
      (s) => s.streamName == 'EEGData',
      orElse: () => throw LSLException('EEG stream not found'),
    );

    final foundMarkerStream = streams.firstWhere(
      (s) => s.streamName == 'MarkerStream',
      orElse: () => throw LSLException('Marker stream not found'),
    );

    // Create inlets
    final eegInlet = await LSL.createInlet<double>(streamInfo: foundEegStream);

    // Create a separate LSL instance for the marker inlet
    final markerInlet = await LSL.createInlet<String>(
      streamInfo: foundMarkerStream,
    );

    print('Created EEG and Marker inlets');

    // Receive samples from both streams
    print('Receiving data from both streams:');

    // Simulate recording session
    for (int i = 0; i < 3; i++) {
      // Pull EEG samples
      final eegSample = await eegInlet.pullSample(timeout: 2.0);
      print('EEG Sample: ${eegSample.data}');

      // Try to pull marker if available
      final markerSample = await markerInlet.pullSample(timeout: 0.1);
      if (markerSample.isNotEmpty) {
        print('Marker: ${markerSample.data[0]}');
      }

      await Future.delayed(Duration(milliseconds: 500));
    }

    // Stop sending samples
    eegCompleter.complete();
    markerCompleter.complete();
    await eegSenderFuture;
    await markerSenderFuture;

    // Clean up

    eegInlet.destroy();
    markerInlet.destroy();
    eegOutlet.destroy();
    markerOutlet.destroy();
    eegInfo.destroy();
    markerInfo.destroy();

    print('All resources cleaned up');
  } catch (e) {
    print('Error: $e');
  }
}

/// Helper function to send EEG samples
Future<void> _sampleSender(dynamic outlet, Completer<void> completer) async {
  int count = 0;

  while (!completer.isCompleted) {
    try {
      // Generate sample data (simulated EEG)
      final sampleData = List.generate(
        outlet.streamInfo.channelCount,
        (i) => (count % 10) / 10 + i * 0.1,
      );

      // Push the sample
      await outlet.pushSample(sampleData);
      count++;

      // Short delay between samples
      await Future.delayed(Duration(milliseconds: 100));
    } catch (e) {
      print('Error sending sample: $e');
      if (!completer.isCompleted) {
        completer.complete();
      }
      break;
    }
  }

  print('Sample sender stopped after $count samples');
}

/// Helper function to send marker events
Future<void> _markerSender(dynamic outlet, Completer<void> completer) async {
  int count = 0;
  final markers = ['start', 'stimulus', 'response', 'end'];

  while (!completer.isCompleted) {
    try {
      // Send a marker every 700ms
      await Future.delayed(Duration(milliseconds: 700));

      if (completer.isCompleted) break;

      // Select a marker
      final marker = markers[count % markers.length];
      await outlet.pushSample([marker]);
      count++;
    } catch (e) {
      print('Error sending marker: $e');
      if (!completer.isCompleted) {
        completer.complete();
      }
      break;
    }
  }

  print('Marker sender stopped after $count markers');
}
