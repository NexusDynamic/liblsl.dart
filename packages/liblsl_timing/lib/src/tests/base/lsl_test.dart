import 'package:liblsl/lsl.dart';
import 'package:liblsl_timing/src/test_config.dart';

mixin LSLStreamHelper {
  final Map<String, LSLStreamInfo> _streamInfoCache = {};
  final Map<String, LSLIsolatedOutlet> _outletCache = {};
  final Map<String, LSLIsolatedInlet> _inletCache = {};

  Map<String, LSLStreamInfo> get streamInfoCache => _streamInfoCache;
  Map<String, LSLIsolatedOutlet> get outletCache => _outletCache;
  Map<String, LSLIsolatedInlet> get inletCache => _inletCache;

  String streamKey(LSLStreamInfo streamInfo) {
    return streamInfo.uid ?? '${streamInfo.streamName}_${streamInfo.sourceId}';
  }

  Future<LSLStreamInfo> createStreamInfo(TestConfiguration config) async {
    final streamInfo = await LSL.createStreamInfo(
      streamName: config.streamName,
      streamType: config.streamType,
      channelCount: config.channelCount,
      sampleRate: config.sampleRate,
      channelFormat: config.channelFormat,
      sourceId: config.sourceId,
    );
    _streamInfoCache[streamKey(streamInfo)] = streamInfo;
    return streamInfo;
  }

  Future<LSLStreamInfo> createStreamInfoFromValues({
    required String streamName,
    required LSLContentType streamType,
    required int channelCount,
    required double sampleRate,
    required LSLChannelFormat channelFormat,
    required String sourceId,
  }) async {
    final streamInfo = await LSL.createStreamInfo(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
    );
    _streamInfoCache[streamKey(streamInfo)] = streamInfo;
    return streamInfo;
  }

  Future<LSLIsolatedOutlet> createOutlet(
    LSLStreamInfo streamInfo, {
    int chunkSize = 1,
    int maxBuffer = 360,
  }) async {
    final key = streamKey(streamInfo);
    if (_outletCache.containsKey(key)) {
      throw Exception('Outlet already exists for stream: $key');
    }
    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );
    _outletCache[key] = outlet;
    return outlet;
  }

  Future<LSLStreamInfo?> findStream(
    String streamName, {
    String? sourceId,
    LSLContentType? streamType,
    String? hostname,
    String? uid,
    int maxStreams = 10,
    double forgetAfter = 5.0,
    double waitTime = 1.0,
  }) async {
    final streams = await LSL.resolveStreams(
      waitTime: waitTime,
      maxStreams: maxStreams,
      forgetAfter: forgetAfter,
    );

    for (final stream in streams) {
      if (stream.streamName == streamName &&
          (sourceId == null || stream.sourceId == sourceId) &&
          (streamType == null || stream.streamType == streamType) &&
          (hostname == null || stream.hostname == hostname) &&
          (uid == null || stream.uid == uid)) {
        return stream;
      }
    }

    return null;
  }

  Future<List<LSLIsolatedInlet>> createInlets(
    List<LSLStreamInfo> streamInfos, {
    int chunkSize = 1,
    int maxBuffer = 360,
    bool recover = true,
  }) async {
    final inlets = <LSLIsolatedInlet>[];
    for (final streamInfo in streamInfos) {
      final inlet = await createInlet(
        streamInfo,
        chunkSize: chunkSize,
        maxBuffer: maxBuffer,
        recover: recover,
      );
      inlets.add(inlet);
    }
    return inlets;
  }

  Future<LSLIsolatedInlet> createInlet(
    LSLStreamInfo streamInfo, {
    int chunkSize = 1,
    int maxBuffer = 360,
    bool recover = true,
  }) async {
    final key = streamKey(streamInfo);
    if (_inletCache.containsKey(key)) {
      throw Exception('Inlet already exists for stream: $key');
    }
    final inlet = await LSL.createInlet(
      streamInfo: streamInfo,
      maxChunkLength: chunkSize,
      maxBufferSize: maxBuffer,
      recover: recover,
    );
    _inletCache[key] = inlet;
    return inlet;
  }

  Future<void> cleanupLSL() async {
    for (final outlet in _outletCache.values) {
      try {
        outlet.destroy();
      } catch (e) {
        print('Error closing outlet: $e');
      }
    }
    for (final inlet in _inletCache.values) {
      try {
        inlet.destroy();
      } catch (e) {
        print('Error closing inlet: $e');
      }
    }
    for (final streamInfo in _streamInfoCache.values) {
      try {
        streamInfo.destroy();
      } catch (e) {
        print('Error closing stream info: $e');
      }
    }
    _outletCache.clear();
    _inletCache.clear();
    _streamInfoCache.clear();
  }
}
