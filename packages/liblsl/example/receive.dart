// Receives the stream that send.dart sends and prints each sample with the
// time it took to arrive. Both are explained in
// docs/streaming-between-devices.md.
//
//   dart run example/receive.dart [samples]
import 'package:liblsl/lsl.dart';

Future<void> main(List<String> args) async {
  final samples = args.isEmpty ? 50 : int.parse(args.first);

  // Look for the stream by name, for up to 10 seconds.
  final streams = await LSL.resolveStreamsByProperty(
    property: LSLStreamProperty.name,
    value: 'GuideStream',
    waitTime: 10.0,
    minStreamCount: 1,
  );
  if (streams.isEmpty) {
    print('No stream named "GuideStream" was found.');
    return;
  }
  final inlet = await LSL.createInlet<double>(streamInfo: streams.first);

  // A sample's timestamp is a reading of the sender's clock. The time
  // correction is the offset that maps it onto this device's clock.
  final offset = await inlet.getTimeCorrection(timeout: 5.0);
  print('Clock offset to the sender: ${(offset * 1000).toStringAsFixed(3)} ms');

  // Samples that arrived while the offset was being measured are discarded,
  // so that each remaining sample is read as it arrives.
  await inlet.flush();

  var received = 0;
  while (received < samples) {
    final sample = await inlet.pullSample(timeout: 2.0);
    if (sample.isEmpty) {
      print('No sample for 2 s; the sender may have stopped.');
      break;
    }
    final sentAt = sample.timestamp + offset;
    final latency = (LSL.localClock() - sentAt) * 1000;
    print(
      'sample ${sample.data[0].toInt()}: ${sample.data[1].toStringAsFixed(3)}'
      '  sent at ${sentAt.toStringAsFixed(4)} s'
      '  latency ${latency.toStringAsFixed(2)} ms',
    );
    received++;
  }

  inlet.destroy();
  streams.destroy();
}
