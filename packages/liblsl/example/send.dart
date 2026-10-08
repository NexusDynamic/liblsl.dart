// Sends a two-channel stream at 10 Hz for others on the network to receive.
// Its counterpart is receive.dart; both are explained in
// docs/streaming-between-devices.md.
//
//   dart run example/send.dart [seconds]
import 'dart:async';
import 'dart:math';

import 'package:liblsl/lsl.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 60 : int.parse(args.first);

  // The description other devices find the stream by. The source id
  // identifies this sender, so that a receiver can reconnect to it after an
  // interruption.
  final info = await LSL.createStreamInfo(
    streamName: 'GuideStream',
    streamType: LSLContentType.custom('Example'),
    channelCount: 2,
    sampleRate: 10.0,
    channelFormat: LSLChannelFormat.double64,
    sourceId: 'guide-sender-1',
  );
  final outlet = await LSL.createOutlet(streamInfo: info);
  print('Sending "GuideStream" for $seconds s.');

  // Channel 1 counts samples, channel 2 is a 0.5 Hz sine wave.
  var count = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    outlet.pushSample([count.toDouble(), sin(2 * pi * 0.5 * count / 10.0)]);
    count++;
  });

  await Future<void>.delayed(Duration(seconds: seconds));
  timer.cancel();
  print('Sent $count samples.');

  outlet.destroy();
  info.destroy();
}
