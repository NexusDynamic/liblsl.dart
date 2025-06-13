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

  @override
  void initState() {
    super.initState();
    _startButtonController.update(WidgetState.disabled, true);
    // get multicast lock
    multicastLock
        .acquireMulticastLock()
        .then((_) {
          // ignore: avoid_print
          print('acquireMulticastLock: success');
        })
        .catchError((e) {
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
          onPressed: () {
            // Start sending data in the background
            _startStream();
          },
          child: const Text('Start Stream (5Hz, 5 seconds)'),
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
      ],
    );
  }

  Future<void> _setupLSL() async {
    _lslver.value = LSL.version;
    _startButtonController.update(WidgetState.disabled, false);
  }

  Future<void> _startStream() async {
    // _completer = Completer<void>();
    try {
      // Update the button states
      _startButtonController.update(WidgetState.disabled, true);
      // Reset the elapsed time
      _elapsedTime.value = 0.0;
      // set a timer to update the elapsed time every second
      final timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedTime.value += 1.0;
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
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Clean up
        outlet.destroy();
        streamInfo.destroy();
      }, debugName: 'LSLTestAppStreamProducer');
      // Stop the timer
      timeTimer.cancel();
      // Update the button states
      _startButtonController.update(WidgetState.disabled, false);
    } catch (e) {
      // ignore: avoid_print
      print('Error: $e');
    }
  }

  @override
  void dispose() {
    multicastLock.releaseMulticastLock();
    _lslver.dispose();
    _startButtonController.dispose();

    super.dispose();
  }
}
