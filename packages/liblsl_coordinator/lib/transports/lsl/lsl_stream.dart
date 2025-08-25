import 'dart:async';

import 'package:liblsl_coordinator/framework.dart';

class LSLStreamInfoHelper {
  // Helper methods for LSL StreamInfo can be added here.
}

/// Factory for creating LSL-based network streams.
class LSLNetworkStreamFactory extends NetworkStreamFactory {
  @override
  Future<DataStream> createDataStream(
    NetworkStreamConfig config, {
    List<Node>? producers,
    List<Node>? consumers,
  }) async {
    // Create and return an LSL stream with the given configuration.
    throw UnimplementedError();
  }

  @override
  Future<CoordinationStream> createCoordinationStream(
    CoordinationStreamConfig config, {
    List<Node>? producers,
    List<Node>? consumers,
  }) async {
    // Create and return an LSL coordination stream with the given configuration.
    throw UnimplementedError();
  }
}

class LSLCoordinationStream extends CoordinationStream {
  LSLCoordinationStream(super.config);

  @override
  FutureOr<void> sendMessage(Message message) {
    // Implement sending a message via LSL here.
    throw UnimplementedError();
  }

  @override
  FutureOr<void> create() {
    // TODO: implement create
    throw UnimplementedError();
  }

  @override
  // TODO: implement created
  bool get created => throw UnimplementedError();

  @override
  // TODO: implement description
  String? get description => throw UnimplementedError();

  @override
  FutureOr<void> dispose() {
    // TODO: implement dispose
    throw UnimplementedError();
  }

  @override
  // TODO: implement disposed
  bool get disposed => throw UnimplementedError();

  @override
  // TODO: implement inbox
  Stream<StringMessage> get inbox => throw UnimplementedError();

  @override
  // TODO: implement manager
  IResourceManager? get manager => throw UnimplementedError();

  @override
  // TODO: implement outbox
  StreamSink<StringMessage> get outbox => throw UnimplementedError();

  @override
  // TODO: implement uId
  String get uId => throw UnimplementedError();

  @override
  FutureOr<void> updateManager(IResourceManager? newManager) {
    // TODO: implement updateManager
    throw UnimplementedError();
  }
}
