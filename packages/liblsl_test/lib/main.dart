import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'dart:math';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';

void main() {
  runApp(LSLTestApp());
}

class LSLTestApp extends StatelessWidget {
  const LSLTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Test App', home: LSLTestPage());
  }
}

class LSLTestPage extends StatefulWidget {
  const LSLTestPage({super.key});

  @override
  State<LSLTestPage> createState() => _LSLTestPageState();
}

class _LSLTestPageState extends State<LSLTestPage> {
  FlutterMulticastLock multicastLock = FlutterMulticastLock();

  final ValueNotifier<double> _elapsedTime = ValueNotifier(0.0);

  final ValueNotifier<int?> _lslver = ValueNotifier(null);

  final WidgetStatesController _startButtonController = WidgetStatesController({
    WidgetState.disabled,
  });

  final WidgetStatesController _checkStreamsButtonController =
      WidgetStatesController({
    WidgetState.disabled,
  });

  final ValueNotifier<List<String>> _resolvedStreams = ValueNotifier([]);
  final ValueNotifier<String?> _sampleData = ValueNotifier(null);
  final ValueNotifier<String?> _streamStatus = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _startButtonController.update(WidgetState.disabled, true);
    _checkStreamsButtonController.update(WidgetState.disabled, true);
    // get multicast lock
    multicastLock.acquireMulticastLock().then((_) {
      // ignore: avoid_print
      print('acquireMulticastLock: success');
    }).catchError((e) {
      // ignore: avoid_print
      print('acquireMulticastLock: error: $e');
    });

    _setupLSL();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ValueListenableBuilder<int?>(
          valueListenable: _lslver,
          builder: (context, version, _) {
            if (version != null) {
              return Text(
                'LSL Version $version',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            } else {
              return Text(
                'Getting LSL Version...',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            }
          },
        ),
        ElevatedButton(
          key: const Key('start_streaming'),
          statesController: _startButtonController,
          onPressed: _startStream,
          child: const Text('Start Stream (5Hz, 5 seconds)'),
        ),
        if (_startButtonController.value.contains(WidgetState.disabled))
          ElevatedButton(
            key: const Key('stop_streaming'),
            onPressed: () {}, // Placeholder for stop functionality
            child: const Text('Stop Stream'),
          ),
        ElevatedButton(
          key: const Key('check_streams'),
          statesController: _checkStreamsButtonController,
          onPressed: _checkStreamsAndSample,
          child: const Text('Check Streams & Sample'),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _elapsedTime,
          builder: (context, sample, _) {
            return Text(
              'Elapsed Time: ${sample.toStringAsFixed(2)} seconds',
              overflow: TextOverflow.visible,
              textScaler: TextScaler.linear(0.5),
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: _streamStatus,
          builder: (context, status, _) {
            return Text(
              status ?? 'Stream status: Not checked',
              key: const Key('stream_status'),
              overflow: TextOverflow.visible,
              textScaler: TextScaler.linear(0.5),
            );
          },
        ),
        ValueListenableBuilder<List<String>>(
          valueListenable: _resolvedStreams,
          builder: (context, streams, _) {
            if (streams.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              children: streams
                  .map((stream) => Text(
                        stream,
                        key: const Key('resolved_streams'),
                        overflow: TextOverflow.visible,
                        textScaler: TextScaler.linear(0.4),
                      ))
                  .toList(),
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: _sampleData,
          builder: (context, sample, _) {
            if (sample == null) {
              return const SizedBox.shrink();
            }
            return Text(
              sample,
              key: const Key('sample_data'),
              overflow: TextOverflow.visible,
              textScaler: TextScaler.linear(0.5),
            );
          },
        ),
      ],
    );
  }

  Future<void> _setupLSL() async {
    final apiConfig = LSLApiConfig(
      ipv6: IPv6Mode.disable,
      // resolveScope: ResolveScope.link,
      // listenAddress: '127.0.0.1', // Use loopback for testing
      // addressesOverride: ['224.0.0.183'],
      // knownPeers: ['127.0.0.1'],
      // sessionId: 'LSLTestSession',
    );
    LSL.setConfigContent(apiConfig);
    _lslver.value = LSL.version;
    _startButtonController.update(WidgetState.disabled, false);
    _checkStreamsButtonController.update(WidgetState.disabled, false);
  }

  Future<void> _startStream() async {
    // _completer = Completer<void>();
    try {
      // Update the button states
      _startButtonController.update(WidgetState.disabled, true);
      setState(() {}); // Trigger UI update to show stop button
      // Reset the elapsed time
      _elapsedTime.value = 0.0;
      // set a timer to update the elapsed time every second
      final timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedTime.value += 1.0;
        debugPrint('Elapsed time: ${_elapsedTime.value} seconds');
      });
      // Start the LSL stream in a separate isolate
      await Isolate.run(() async {
        final completer = Completer<void>();
        // Create a stream info object
        final streamInfo = await LSL.createStreamInfo(
          streamName: 'FlutterApp',
          channelCount: 2,
          channelFormat: LSLChannelFormat.float32,
          sampleRate: 5.0,
          streamType: LSLContentType.eeg,
          sourceId: 'FlutterAppDevice',
        );

        // Create an outlet
        final outlet = await LSL.createOutlet(
          streamInfo: streamInfo,
          chunkSize: 1,
          maxBuffer: 10,
          useIsolates: false,
        );
        final rng = Random();

        final productionDuration = Duration(seconds: 5);
        Timer(productionDuration, () {
          // Complete the completer after the production duration
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
        while (!completer.isCompleted) {
          // Create a sample with random data
          final sample = List<double>.generate(
            streamInfo.channelCount,
            (index) => rng.nextDouble(),
          );
          // Send the sample
          final result = await outlet.pushSample(sample);
          if (result != 0) {
            // ignore: avoid_print
            print('Error pushing sample: $result');
          }
          debugPrint('Pushed sample: $sample');
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Clean up
        await outlet.destroy();
        debugPrint('Outlet destroyed');
        streamInfo.destroy();
        debugPrint('StreamInfo destroyed');
      }, debugName: 'LSLTestAppStreamProducer');
      // Stop the timer
      debugPrint('Stopping timer');
      timeTimer.cancel();
      // Update the button states
      debugPrint('Enabling start button');
      _startButtonController.update(WidgetState.disabled, false);
      setState(() {}); // Trigger UI update to hide stop button
      debugPrint('Stream finished');
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Error: $e');
    }
  }

  Future<void> _checkStreamsAndSample() async {
    try {
      _checkStreamsButtonController.update(WidgetState.disabled, true);
      _streamStatus.value = "Checking streams...";
      _resolvedStreams.value = [];
      _sampleData.value = null;

      // Resolve available streams
      final List<int> streamAddrs = await Isolate.run(() async {
        final streams = await LSL.resolveStreamsByProperty(
            property: LSLStreamProperty.sourceId,
            value: 'FlutterAppDevice',
            waitTime: 2.0,
            maxStreams: 1);
        debugPrint('Resolved ${streams.length} stream(s)');
        return streams.map((s) => s.streamInfo.address).toList();
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('Timeout while resolving streams');
        return <int>[];
      });

      if (streamAddrs.isEmpty) {
        _streamStatus.value = "No streams found";
        _checkStreamsButtonController.update(WidgetState.disabled, false);
        return;
      }

      final streams = <LSLStreamInfo>[];
      for (final addr in streamAddrs) {
        final info = LSLStreamInfo.fromStreamInfoAddr(addr);
        streams.add(info);
      }

      _resolvedStreams.value = streams
          .map((s) =>
              "Stream: ${s.streamName}, Channels: ${s.channelCount}, Format: ${s.channelFormat}")
          .toList();

      _streamStatus.value = "Found ${streams.length} stream(s)";

      if (streams.isNotEmpty) {
        // Verify stream properties
        final stream = streams[0];
        if (stream.streamName == 'FlutterApp' &&
            stream.channelCount == 2 &&
            stream.channelFormat == LSLChannelFormat.float32) {
          // Create inlet and pull sample
          _streamStatus.value = "Creating inlet...";
          final inlet = await LSL.createInlet(streamInfo: stream);

          if (inlet.streamInfo.streamName == 'FlutterApp') {
            _streamStatus.value = "Pulling sample...";

            // Pull a sample
            final sample = await inlet.pullSample(timeout: 1.0);

            if (sample.errorCode == 0 && sample.data.length == 2) {
              _sampleData.value =
                  "Sample: [${sample.data[0].toStringAsFixed(4)}, ${sample.data[1].toStringAsFixed(4)}]";
              _streamStatus.value = "Sample received successfully!";
            } else {
              _sampleData.value = "Error: ${sample.errorCode}";
              _streamStatus.value = "Failed to receive sample";
            }
          }

          // Clean up
          await inlet.destroy();
        } else {
          _streamStatus.value = "Stream properties don't match expected values";
        }
      }

      streams.destroy();
    } catch (e) {
      _streamStatus.value = "Error: $e";
      debugPrint('Error checking streams: $e');
    } finally {
      _checkStreamsButtonController.update(WidgetState.disabled, false);
    }
  }

  @override
  void dispose() {
    multicastLock.releaseMulticastLock();
    _lslver.dispose();
    _startButtonController.dispose();
    _checkStreamsButtonController.dispose();
    _resolvedStreams.dispose();
    _sampleData.dispose();
    _streamStatus.dispose();

    super.dispose();
  }
}
