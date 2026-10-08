// A minimal coordinated experiment. Every device runs this program: one is
// elected coordinator, waits for the others, starts a data stream on all of
// them at a scheduled time, announces three trials and stops. It is explained in
// docs/coordinated-experiment.md.
//
//   dart run example/experiment.dart <device name> [number of devices]
import 'dart:async';
import 'dart:io';

import 'package:liblsl_coordinator/liblsl_coordinator.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

Future<void> main(List<String> args) async {
  final name = args.isNotEmpty ? args[0] : 'device';
  final devices = args.length > 1 ? int.parse(args[1]) : 2;

  // Devices find each other by the experiment and session names. The
  // transport is the only part of this configuration that is specific to
  // Lab Streaming Layer.
  final session = PeerSession.create(
    CoordinationConfig(
      name: 'guide_experiment',
      sessionConfig: CoordinationSessionConfig(
        name: 'session_1',
        maxNodes: devices,
      ),
      transportConfig: LSLTransportConfig(),
    ),
    thisNodeConfig: NodeConfigFactory().defaultConfig().copyWith(name: name),
  );

  final finished = Completer<void>();
  Timer? sender;

  // Each device sends one sample every 500 ms and prints the samples it
  // receives from the others, with the time each spent in transit.
  void exchange(DataStream stream) {
    stream.inbox.listen((message) {
      final from = senderOf(message, session);
      if (from == name) return;
      final transit = message.timing?.transitSeconds;
      final ms = transit == null ? '?' : (transit * 1000).toStringAsFixed(2);
      print('$name received ${message.data.first} from $from after $ms ms');
    });
    var count = 0;
    sender = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (stream.started) stream.sendData([(count++).toDouble()]);
    });
  }

  // Participants act on what the coordinator announces.
  session.events.streamStart.listen((event) async {
    if (!session.isCoordinator) {
      exchange(await session.getDataStream(event.streamName));
    }
  });
  session.events.streamStop.listen((_) => sender?.cancel());
  session.events.userCoordinationMessages.listen((event) {
    print('$name: ${event.description}');
    if (event.messageType == 'end' && !finished.isCompleted) {
      finished.complete();
    }
  });

  await session.initialize();
  await session.join();
  print(
    '$name joined as ${session.isCoordinator ? 'coordinator' : 'participant'}',
  );

  if (session.isCoordinator) {
    // Wait for every device, then close the session to newcomers.
    await session.waitForMinNodes(devices);
    await session.pauseAcceptingNodes();

    final stream = await session.createDataStream(
      DataStreamConfig(
        name: 'Samples',
        channels: 1,
        sampleRate: 2.0,
        dataType: StreamDataType.double64,
        participationMode: StreamParticipationMode.allNodes,
      ),
    );
    // Every device starts the stream at the same instant, two seconds from
    // now.
    await session.startStream(
      'Samples',
      startAt: DateTime.now().add(const Duration(seconds: 2)),
    );
    exchange(stream);

    for (var trial = 1; trial <= 3; trial++) {
      await session.sendUserMessage('trial', 'Trial $trial', {'trial': trial});
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    await session.stopStream('Samples');
    sender?.cancel();
    await session.sendUserMessage('end', 'End of experiment');
  } else {
    await finished.future;
  }

  await session.leave();
  await session.dispose();
  exit(0);
}

/// The name of the device that sent [message].
///
/// The LSL transport identifies a sender as `stream//role//uId//id`.
String senderOf(IMessage message, PeerSession session) {
  final parts = (message.timing?.sourceId ?? '').split('//');
  final uId = parts.length >= 4 ? parts[2] : parts.first;
  for (final node in session.connectedNodes) {
    if (node.uId == uId) return node.name;
  }
  return uId;
}
