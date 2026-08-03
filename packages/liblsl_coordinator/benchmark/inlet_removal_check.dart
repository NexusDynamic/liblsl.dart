// Smoke test for StreamInletIsolate.removeInlet: samples must stop arriving
// after removal (previously the removal silently did nothing).
import 'dart:async';
import 'dart:io';
import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

Future<void> main() async {
  LSL.setConfigContent(
    LSLApiConfig(
      ipv6: IPv6Mode.disable,
      resolveScope: ResolveScope.link,
      listenAddress: '127.0.0.1',
      addressesOverride: ['224.0.0.185'],
      knownPeers: ['127.0.0.1'],
      logLevel: -2,
    ),
  );

  final info = await LSL.createStreamInfo(
    streamName: 'RemovalTest',
    streamType: LSLContentType.markers,
    channelCount: 1,
    channelFormat: LSLChannelFormat.double64,
    sampleRate: 100.0,
    sourceId: 'removal-test-src',
  );
  final outlet = await LSL.createOutlet(streamInfo: info);

  final resolved = await LSL.resolveStreamsByPredicate(
    predicate: "source_id='removal-test-src'",
    waitTime: 3.0,
    minStreamCount: 1,
  );
  if (resolved.isEmpty) {
    stderr.writeln('FAIL: could not resolve test stream');
    exit(1);
  }
  final addr = resolved.first.streamInfo.address;

  final isolate = IsolateStreamManager.createInletIsolate(
    streamId: 'removal-test',
    dataType: StreamDataType.double64,
    useBusyWaitInlets: false,
    useBusyWaitOutlets: false,
    pollingInterval: Duration(milliseconds: 5),
    initialInletAddresses: [addr],
  );
  await isolate.create();

  var received = 0;
  final sub = isolate.incomingData.listen((_) => received++);
  await isolate.start();

  final pushTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
    outlet.pushSample([DateTime.now().millisecondsSinceEpoch.toDouble()]);
  });

  await Future.delayed(Duration(seconds: 2));
  final beforeRemoval = received;

  await isolate.removeInlet(addr);
  await Future.delayed(Duration(milliseconds: 200)); // drain in-flight
  final atRemoval = received;
  await Future.delayed(Duration(seconds: 2));
  final afterRemoval = received;

  pushTimer.cancel();
  await sub.cancel();
  await isolate.stop();
  await isolate.dispose();
  outlet.destroy();
  info.destroy();

  print('received before removal: $beforeRemoval');
  print('received after removal:  ${afterRemoval - atRemoval}');
  if (beforeRemoval > 50 && afterRemoval == atRemoval) {
    print('PASS: inlet removal stops sample delivery');
    exit(0);
  }
  stderr.writeln('FAIL: expected >50 before and 0 after removal');
  exit(1);
}
