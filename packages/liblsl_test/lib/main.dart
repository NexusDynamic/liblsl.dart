import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'dart:math';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Test App', home: MyApp2());
  }
}

class MyApp2 extends StatefulWidget {
  const MyApp2({super.key});

  @override
  State<MyApp2> createState() => _MyApp2State();
}

class _MyApp2State extends State<MyApp2> {
  MethodChannel? rtNetworkingChannel;

  late Future<int> _lslver;
  Completer<void>? _completer;

  @override
  void initState() {
    super.initState();
    _lslver = setupLSL();
    if (defaultTargetPlatform == TargetPlatform.android) {
      // get multicast lock
      if (rtNetworkingChannel == null) {
        rtNetworkingChannel = MethodChannel('com.zeyus.liblsl_test/Networking');

        rtNetworkingChannel!
            .invokeMethod('acquireMulticastLock')
            .then((_) {
              // ignore: avoid_print
              print('acquireMulticastLock: success');
            })
            .catchError((e) {
              // ignore: avoid_print
              print('acquireMulticastLock: error: $e');
            });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FutureBuilder<int>(
          future: _lslver,
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            if (snapshot.hasData) {
              return Text(
                'LSL Version ${snapshot.data}',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            } else if (snapshot.hasError) {
              return Text(
                'Error: ${snapshot.error}',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            } else {
              return Text(
                'Calculating answer...',
                overflow: TextOverflow.visible,
                textScaler: TextScaler.linear(0.5),
              );
            }
          },
        ),

        ElevatedButton(
          key: const Key('start_streaming'),
          onPressed: () async {
            _completer = Completer<void>();
            // Start sending data in the background
            startStream(_completer!);
          },
          child: const Text('Start Stream'),
        ),
        ElevatedButton(
          key: const Key('stop_streaming'),
          onPressed: () async {
            if (_completer != null && !_completer!.isCompleted) {
              _completer!.complete();
            }
          },
          child: const Text('Stop Stream'),
        ),
        // add resolve and other LSL functions here
      ],
    );
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      rtNetworkingChannel
          ?.invokeMethod('releaseMulticastLock')
          .then((_) {
            // ignore: avoid_print
            print('releaseMulticastLock: success');
          })
          .catchError((e) {
            // ignore: avoid_print
            print('releaseMulticastLock: error: $e');
          });
    }
    super.dispose();
  }
}

Future<int> setupLSL() async {
  return LSL.version;
}

Future<void> startStream(Completer completer) async {
  try {
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
      chunkSize: 0,
      maxBuffer: 360,
    );
    final rng = Random();
    while (!completer.isCompleted) {
      await Future.delayed(const Duration(milliseconds: 200));
      // Create a sample with random data
      final sample = List<double>.generate(
        streamInfo.channelCount,
        (index) => rng.nextDouble(),
      );
      // Send the sample
      await outlet.pushSample(sample);
    }

    // Clean up
    outlet.destroy();
    streamInfo.destroy();
  } catch (e) {
    // ignore: avoid_print
    print('Error: $e');
  }
}
