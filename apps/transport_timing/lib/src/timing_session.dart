import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';
import 'package:peer_coordinator/websocket.dart';
import 'package:timing_core/timing_core.dart';
import 'package:webrtc_coordinator_flutter/webrtc_coordinator_flutter.dart';

import 'log_store.dart';
import 'raw_lsl_run.dart';
import 'settings.dart';
import 'stream_run.dart';

/// The `messageType` of the message that announces a run to every device.
const String _runMessage = 'tt_run';

/// How long after its last send a device keeps logging what arrives.
const Duration _drain = Duration(seconds: 1);

enum SessionStatus { idle, connecting, connected, ended, failed }

/// One device in the session, as the roster shows it.
class Member {
  const Member({
    required this.uId,
    required this.name,
    required this.isSelf,
    required this.isCoordinator,
  });

  final String uId;
  final String name;
  final bool isSelf;
  final bool isCoordinator;
}

/// The run this device is in.
class ActiveRun {
  const ActiveRun(this.config, this.status, {this.queued = 0});

  final RunConfig config;
  final String status;

  /// Runs still to come after this one (coordinator only).
  final int queued;
}

/// A finished run: where its log is and what this device alone saw.
class RunResult {
  const RunResult(this.config, this.path, this.report);

  final RunConfig config;
  final String path;
  final String report;
}

/// A session of devices that run timing tests together.
///
/// Election, membership and the data streams are `peer_coordinator`'s. This
/// adds one message, by which the coordinator announces a run, and the
/// recording of each run to a log.
class TimingSession {
  TimingSession({
    required this.settings,
    ITransportConfig? transportConfig,
    String? backendKey,
    double Function()? clock,
    LogStore? store,
    this.heartbeatInterval = const Duration(seconds: 2),
    this.discoveryInterval = const Duration(seconds: 2),
    this.nodeTimeout = const Duration(seconds: 8),
  }) : _transportConfig = transportConfig,
       _backendKey = backendKey ?? settings.backend.key,
       _isLsl = transportConfig == null
           ? settings.backend == Backend.lsl
           : transportConfig is LSLTransportConfig,
       _store = store ?? LogStore() {
    // LSL reports receive times on its own clock; the other transports on
    // PeerClock. Local events have to be read on the same one.
    _clock = clock ?? (_isLsl ? LSL.localClock : PeerClock.now);
  }

  final AppSettings settings;

  /// Injected by tests; the app's comes from [settings].
  final ITransportConfig? _transportConfig;
  final String _backendKey;
  final bool _isLsl;
  final LogStore _store;
  late final double Function() _clock;

  final Duration heartbeatInterval;
  final Duration discoveryInterval;
  final Duration nodeTimeout;

  final ValueNotifier<SessionStatus> status = ValueNotifier(SessionStatus.idle);
  final ValueNotifier<List<Member>> roster = ValueNotifier(const []);
  final ValueNotifier<bool> isCoordinator = ValueNotifier(false);
  final ValueNotifier<ActiveRun?> run = ValueNotifier(null);
  final ValueNotifier<List<RunResult>> results = ValueNotifier(const []);

  /// Counts the samples received in an interactive run; the screen flashes
  /// on each change.
  final ValueNotifier<int> flash = ValueNotifier(0);

  /// Why [connect] failed or the session ended, to show as it is.
  String? notice;

  PeerSession? _session;
  final List<StreamSubscription<void>> _subscriptions = [];

  /// Stream-path runs announced and waiting for their stream to start.
  final Map<String, RunConfig> _announced = {};
  StreamRun? _streamRun;
  RunLogWriter? _log;
  bool _busy = false;

  ITransportConfig _buildTransportConfig() {
    final injected = _transportConfig;
    if (injected != null) return injected;
    if (settings.backend == Backend.lsl) {
      return LSLTransportConfig(
        lslApiConfig: LSLApiConfig(ipv6: IPv6Mode.disable),
      );
    }
    final hubUri = Uri.parse(settings.hubUrl);
    final credentials = HubCredentials(
      session: settings.sessionName,
      secret: settings.hubSecret,
    );
    return settings.backend == Backend.websocket
        ? WebSocketTransportConfig(hubUri: hubUri, credentials: credentials)
        : RtcTransportConfig(
            hubUri: hubUri,
            credentials: credentials,
            adapterFactory: flutterWebrtcAdapterFactory,
          );
  }

  /// Joins the session. Failures land in [status] and [notice].
  Future<bool> connect({Duration timeout = const Duration(seconds: 20)}) async {
    if (status.value == SessionStatus.connecting) return false;
    status.value = SessionStatus.connecting;
    notice = null;

    try {
      final session = PeerSession.create(
        CoordinationConfig(
          name: 'transport_timing',
          sessionConfig: CoordinationSessionConfig(
            name: settings.sessionName,
            maxNodes: 32,
            heartbeatInterval: heartbeatInterval,
            discoveryInterval: discoveryInterval,
            nodeTimeout: nodeTimeout,
          ),
          topologyConfig: HierarchicalTopologyConfig(maxNodes: 32),
          transportConfig: _buildTransportConfig(),
        ),
        thisNodeConfig: NodeConfig(
          name: settings.deviceName,
          id: settings.deviceName,
          capabilities: {
            NodeCapability.coordinator,
            NodeCapability.participant,
          },
        ),
      );
      _session = session;

      // Before joining: the event stream buffers nothing.
      _subscriptions
        ..add(session.events.userMessages.listen(_onUserMessage))
        ..add(session.events.streamStart.listen(_onStreamStart))
        ..add(session.events.nodeJoined.listen((_) => _refresh()))
        ..add(session.events.nodeLeft.listen((_) => _refresh()))
        ..add(session.events.phaseChanges.listen((_) => _refresh()))
        ..add(session.events.sessionEnded.listen(_onSessionEnded));

      await session.initialize();
      await session.join(timeout);
    } catch (e) {
      notice = '$e';
      status.value = SessionStatus.failed;
      await _teardown();
      return false;
    }
    status.value = SessionStatus.connected;
    _refresh();
    return true;
  }

  Future<void> leave() async {
    await _teardown();
    status.value = SessionStatus.ended;
  }

  void dispose() {
    unawaited(_teardown());
    status.dispose();
    roster.dispose();
    isCoordinator.dispose();
    run.dispose();
    results.dispose();
    flash.dispose();
  }

  // ---------------------------------------------------------------------------
  // Coordinator: starting runs
  // ---------------------------------------------------------------------------

  /// Runs [configs] one after another on every device. Coordinator only.
  Future<void> startRuns(List<RunConfig> configs) async {
    final session = _session;
    if (session == null || !session.isCoordinator || _busy) return;
    for (final (index, config) in configs.indexed) {
      if (_session != session) return;
      final nodes = roster.value.length;
      await session.sendUserMessage(_runMessage, config.summary, {
        ...config.toMap(),
        'nodes': nodes,
      });
      final queued = configs.length - index - 1;
      if (config.path == DataPath.rawLsl) {
        await _runRaw(config, nodes, queued: queued);
      } else {
        await _coordinateStreamRun(session, config, queued: queued);
      }
      // Let every device finish writing before the next run is announced.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _coordinateStreamRun(
    PeerSession session,
    RunConfig config, {
    required int queued,
  }) async {
    if (_busy) return;
    _busy = true;
    final name = _streamName(config);
    try {
      run.value = ActiveRun(config, 'Starting stream', queued: queued);
      final stream = await session.createDataStream(
        DataStreamConfig(
          name: name,
          channels: config.channels,
          sampleRate: config.sampleRate,
          dataType: StreamDataType.double64,
          participationMode: StreamParticipationMode.allNodes,
          precisePolling: config.precisePolling,
        ),
      );
      await session.startStream(name);
      await _recordStreamRun(stream, config, queued: queued);
      // The participants stop on their own clocks, a moment after this
      // device; the stream goes once they have.
      await Future<void>.delayed(_drain);
      await session.stopStream(name);
      await session.destroyStream(name);
    } catch (e) {
      debugPrint('run ${config.runId} failed: $e');
      run.value = null;
    } finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Every device: taking part in a run
  // ---------------------------------------------------------------------------

  void _onUserMessage(UserMessageEvent event) {
    if (event.messageType != _runMessage) return;
    // The coordinator hears its own announcement on some transports, and it
    // is already running.
    if (_session?.isCoordinator ?? true) return;
    final config = RunConfig.fromMap(event.payload);
    if (config.path == DataPath.rawLsl) {
      unawaited(_runRaw(config, event.payload['nodes'] as int, queued: 0));
    } else {
      _announced[_streamName(config)] = config;
    }
  }

  Future<void> _onStreamStart(StreamStartEvent event) async {
    final config = _announced.remove(event.streamName);
    if (config == null) return;
    while (_busy && _session != null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final session = _session;
    if (session == null) return;
    _busy = true;
    try {
      final stream = await session.getDataStream(event.streamName);
      await _recordStreamRun(stream, config, queued: 0);
    } catch (e) {
      debugPrint('run ${config.runId} failed: $e');
      run.value = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> _recordStreamRun(
    DataStream stream,
    RunConfig config, {
    required int queued,
  }) async {
    final buffer = StringBuffer();
    final header = _header(config);
    final log = RunLogWriter(buffer, header);
    final streamRun = StreamRun(
      stream: stream,
      config: config,
      log: log,
      clock: _clock,
      onSample: config.test == TestKind.interactive ? _onInteractive : null,
    );
    _log = log;
    _streamRun = streamRun;
    log.event(_clock(), 'started');
    streamRun.start();

    for (var left = config.durationSeconds; left > 0; left--) {
      run.value = ActiveRun(
        config,
        '${left}s left, sent ${streamRun.sent}, received ${streamRun.received}',
        queued: queued,
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    run.value = ActiveRun(config, 'Finishing', queued: queued);
    await Future<void>.delayed(_drain);
    _streamRun = null;
    _log = null;
    await streamRun.finish();
    log.event(_clock(), 'stopped');
    await _save(config, header, buffer);
  }

  Future<void> _runRaw(
    RunConfig config,
    int nodes, {
    required int queued,
  }) async {
    // A run can be announced while this device is still saving the last.
    while (_busy && _session != null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final session = _session;
    if (session == null) return;
    _busy = true;
    try {
      final buffer = StringBuffer();
      final header = _header(config);
      await runRawLsl(
        config: config,
        nodeUId: session.thisNode.uId,
        expectedNodes: nodes,
        log: RunLogWriter(buffer, header),
        onStatus: (status) =>
            run.value = ActiveRun(config, status, queued: queued),
      );
      await _save(config, header, buffer);
    } catch (e) {
      debugPrint('run ${config.runId} failed: $e');
      run.value = null;
    } finally {
      _busy = false;
    }
  }

  /// Interactive runs: the screen was touched. Sends a sample and logs the
  /// touch against it.
  void touch() {
    final streamRun = _streamRun;
    if (streamRun == null || streamRun.config.test != TestKind.interactive) {
      return;
    }
    final touched = _clock();
    _log?.marker('touch', streamRun.send(), touched);
  }

  /// Interactive runs: a sample arrived. Flashes the screen and logs when
  /// the frame showing it was drawn.
  void _onInteractive(String fromUId, int seq) {
    flash.value++;
    final log = _log;
    SchedulerBinding.instance
      ..addPostFrameCallback(
        (_) => log?.marker('shown', seq, _clock(), sourceId: fromUId),
      )
      ..scheduleFrame();
  }

  String _streamName(RunConfig config) => 'tt_${config.runId}';

  RunHeader _header(RunConfig config) {
    final raw = config.path == DataPath.rawLsl;
    // Mirrors LSLNetworkStream._getPollingInterval in liblsl_coordinator:
    // an LSL data stream polls at the sample period, within these bounds.
    final period = (1e6 / config.sampleRate).round();
    final lslPoll =
        (config.precisePolling
            ? period.clamp(100, 10000)
            : period.clamp(1000, 10000)) /
        1e6;
    return RunHeader(
      runId: config.runId,
      startedAt: DateTime.now(),
      deviceId: _session!.thisNode.uId,
      deviceName: settings.deviceName,
      sourceId: _session!.thisNode.uId,
      test: config.test.name,
      backend: raw ? 'lsl' : _backendKey,
      sampleRate: config.test == TestKind.interactive ? 0 : config.sampleRate,
      channels: config.channels,
      receiveMode: raw
          ? config.receiveMode.key
          : !_isLsl
          ? 'event'
          : config.precisePolling
          ? 'busy-wait'
          : 'polled',
      pollInterval: raw
          ? (config.receiveMode == ReceiveMode.polled
                ? config.pollIntervalMicros / 1e6
                : null)
          : _isLsl
          ? lslPoll
          : null,
      sendMode: raw ? config.sendMode.key : 'stream',
      extra: {
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
        'durationSeconds': config.durationSeconds,
        if (raw) 'pushthrough': config.pushthrough,
      },
    );
  }

  Future<void> _save(
    RunConfig config,
    RunHeader header,
    StringBuffer buffer,
  ) async {
    run.value = ActiveRun(config, 'Saving');
    final content = buffer.toString();
    final file = await _store.save(header, content);
    final report = await Isolate.run(
      () => formatReport(
        analyse([RunLog.parse(const LineSplitter().convert(content))]),
      ),
    );
    results.value = [...results.value, RunResult(config, file.path, report)];
    run.value = null;
  }

  // ---------------------------------------------------------------------------
  // Session state
  // ---------------------------------------------------------------------------

  void _onSessionEnded(SessionEndedEvent event) {
    if (status.value == SessionStatus.ended) return;
    notice = switch (event.reason) {
      SessionEndReason.coordinatorLeft => 'The coordinator left.',
      SessionEndReason.coordinatorTimedOut =>
        'Lost contact with the coordinator.',
      SessionEndReason.coordinatorTransportLost =>
        'The connection to the coordinator dropped.',
      SessionEndReason.evicted => 'This device was disconnected.',
    };
    roster.value = const [];
    status.value = SessionStatus.ended;
    unawaited(_teardown());
  }

  void _refresh() {
    final session = _session;
    if (session == null || status.value == SessionStatus.ended) return;
    isCoordinator.value = session.isCoordinator;
    // connectedNodes is the coordinator's view; whether it lists this node
    // depends on the role, so merge it in.
    final byUId = <String, Member>{
      session.thisNode.uId: Member(
        uId: session.thisNode.uId,
        name: session.thisNode.name,
        isSelf: true,
        isCoordinator: session.isCoordinator,
      ),
    };
    for (final node in session.connectedNodes) {
      byUId.putIfAbsent(
        node.uId,
        () => Member(
          uId: node.uId,
          name: node.name,
          isSelf: false,
          isCoordinator: node.uId == session.coordinatorUId,
        ),
      );
    }
    roster.value = byUId.values.toList(growable: false);
  }

  Future<void> _teardown() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _streamRun?.finish();
    _streamRun = null;
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await session.dispose();
    } catch (e) {
      debugPrint('session teardown: $e');
    }
  }
}
