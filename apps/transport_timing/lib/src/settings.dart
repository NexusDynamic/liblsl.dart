import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// What carries the session: coordination always, and the samples too unless
/// a run uses [DataPath.rawLsl].
enum Backend {
  lsl('lsl-coordinator', 'LSL'),
  websocket('websocket', 'WebSocket hub'),
  webrtc('webrtc', 'WebRTC');

  const Backend(this.key, this.label);

  /// How run logs name it.
  final String key;
  final String label;

  bool get needsHub => this != lsl;
}

/// This device's settings, remembered between launches.
class AppSettings {
  String deviceName;

  /// Devices only find each other within a session.
  String sessionName;
  Backend backend;
  String hubUrl;
  String hubSecret;

  /// LSL backend: receive without polling
  /// (`LSLTransportConfig.eventDrivenInlets`). Each device chooses for
  /// itself; its logs record which it used.
  bool eventDrivenLsl;

  AppSettings({
    required this.deviceName,
    this.sessionName = 'timing',
    this.backend = Backend.lsl,
    this.hubUrl = 'ws://192.168.1.10:8080',
    this.hubSecret = '',
    this.eventDrivenLsl = false,
  });

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      deviceName:
          prefs.getString('device_name') ??
          'device${Random().nextInt(900) + 100}',
      sessionName: prefs.getString('session_name') ?? 'timing',
      backend:
          Backend.values.asNameMap()[prefs.getString('backend')] ?? Backend.lsl,
      hubUrl: prefs.getString('hub_url') ?? 'ws://192.168.1.10:8080',
      hubSecret: prefs.getString('hub_secret') ?? '',
      eventDrivenLsl: prefs.getBool('event_driven_lsl') ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', deviceName);
    await prefs.setString('session_name', sessionName);
    await prefs.setString('backend', backend.name);
    await prefs.setString('hub_url', hubUrl);
    await prefs.setString('hub_secret', hubSecret);
    await prefs.setBool('event_driven_lsl', eventDrivenLsl);
  }
}

enum TestKind { latency, interactive }

/// How a run's samples travel.
enum DataPath {
  /// A coordinator data stream on the session's backend.
  stream,

  /// liblsl outlets and inlets used directly, to measure LSL itself.
  rawLsl,
}

/// How a [DataPath.rawLsl] run receives.
enum ReceiveMode {
  /// Blocks inside liblsl until a sample arrives: no polling delay.
  event('event', 'Event-driven (blocking pull)'),

  /// Polls without pausing: no polling delay, one core per inlet.
  busyWait('busy-wait', 'Busy-wait'),

  /// Drains the inlet, then sleeps for the poll interval.
  polled('polled', 'Polled');

  const ReceiveMode(this.key, this.label);
  final String key;
  final String label;
}

/// How a [DataPath.rawLsl] run sends.
enum SendMode {
  /// `pushSampleSync`: liblsl queues the sample and its own thread sends it.
  sync('sync', 'Sync push'),

  /// `pushSampleSync` on a `syncBlocking` outlet: the push itself writes to
  /// every consumer's socket and returns when the OS has the data.
  syncBlocking('sync-blocking', 'Sync push, blocking socket writes'),

  /// `pushSample` through the outlet's isolate.
  async('async', 'Async push (isolate)');

  const SendMode(this.key, this.label);
  final String key;
  final String label;
}

/// One run, as the coordinator sends it to every device.
class RunConfig {
  final String runId;
  final TestKind test;
  final DataPath path;
  final double sampleRate;

  /// Channels per sample; the first carries the sequence number, the rest
  /// pad the sample to the size being tested.
  final int channels;
  final int durationSeconds;

  /// [DataPath.stream] over LSL: busy-wait rather than timer polling.
  final bool precisePolling;

  final ReceiveMode receiveMode;
  final int pollIntervalMicros;
  final SendMode sendMode;

  /// In a sweep: which repetition of the conditions this run belongs to and
  /// where it came in the sweep, both from 1. Null for a run on its own.
  final int? repetition;
  final int? sweepOrder;

  const RunConfig({
    required this.runId,
    this.test = TestKind.latency,
    this.path = DataPath.stream,
    this.sampleRate = 100,
    this.channels = 1,
    this.durationSeconds = 30,
    this.precisePolling = true,
    this.receiveMode = ReceiveMode.event,
    this.pollIntervalMicros = 1000,
    this.sendMode = SendMode.sync,
    this.repetition,
    this.sweepOrder,
  });

  static String newRunId() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = DateTime.now();
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0')}';
  }

  /// A short description for lists and status lines.
  String get summary {
    if (test == TestKind.interactive) return 'interactive, ${durationSeconds}s';
    final how = path == DataPath.stream
        ? 'stream'
        : 'raw LSL, ${receiveMode.key}'
              '${receiveMode == ReceiveMode.polled ? ' ${pollIntervalMicros}us' : ''}'
              ', ${sendMode.key}';
    return '${sampleRate.toStringAsFixed(0)} Hz x $channels ch, '
        '${durationSeconds}s, $how'
        '${repetition == null ? '' : ', repetition $repetition'}';
  }

  RunConfig copyWith({
    String? runId,
    TestKind? test,
    DataPath? path,
    double? sampleRate,
    int? channels,
    int? durationSeconds,
    bool? precisePolling,
    ReceiveMode? receiveMode,
    int? pollIntervalMicros,
    SendMode? sendMode,
    int? repetition,
    int? sweepOrder,
  }) => RunConfig(
    runId: runId ?? this.runId,
    test: test ?? this.test,
    path: path ?? this.path,
    sampleRate: sampleRate ?? this.sampleRate,
    channels: channels ?? this.channels,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    precisePolling: precisePolling ?? this.precisePolling,
    receiveMode: receiveMode ?? this.receiveMode,
    pollIntervalMicros: pollIntervalMicros ?? this.pollIntervalMicros,
    sendMode: sendMode ?? this.sendMode,
    repetition: repetition ?? this.repetition,
    sweepOrder: sweepOrder ?? this.sweepOrder,
  );

  Map<String, dynamic> toMap() => {
    'runId': runId,
    'test': test.name,
    'path': path.name,
    'sampleRate': sampleRate,
    'channels': channels,
    'durationSeconds': durationSeconds,
    'precisePolling': precisePolling,
    'receiveMode': receiveMode.name,
    'pollIntervalMicros': pollIntervalMicros,
    'sendMode': sendMode.name,
    // Raw runs send every sample at once: outlet and inlet both have a
    // chunk size of one, which leaves liblsl's pushthrough flag nothing to
    // decide. Still sent for devices on a version that reads it.
    'pushthrough': true,
    'repetition': ?repetition,
    'sweepOrder': ?sweepOrder,
  };

  factory RunConfig.fromMap(Map<String, dynamic> map) => RunConfig(
    runId: map['runId'] as String,
    test: TestKind.values.byName(map['test'] as String),
    path: DataPath.values.byName(map['path'] as String),
    sampleRate: (map['sampleRate'] as num).toDouble(),
    channels: map['channels'] as int,
    durationSeconds: map['durationSeconds'] as int,
    precisePolling: map['precisePolling'] as bool,
    receiveMode: ReceiveMode.values.byName(map['receiveMode'] as String),
    pollIntervalMicros: map['pollIntervalMicros'] as int,
    sendMode: SendMode.values.byName(map['sendMode'] as String),
    repetition: map['repetition'] as int?,
    sweepOrder: map['sweepOrder'] as int?,
  );

  /// Every receive and send mode of raw LSL, otherwise like [base],
  /// [repetitions] times over.
  ///
  /// One run of a condition says little about it: the same condition run
  /// twice can differ by more than two conditions do. And conditions run in
  /// a fixed order are compared at different times, as the devices warm up
  /// and the network changes. So each repetition runs every condition once,
  /// in an order of its own.
  static List<RunConfig> rawLslSweep(
    RunConfig base, {
    int repetitions = 3,
    Random? random,
  }) {
    final conditions = [
      for (final receive in ReceiveMode.values)
        for (final send in SendMode.values) (receive, send),
    ];
    final runs = <RunConfig>[];
    for (var repetition = 1; repetition <= repetitions; repetition++) {
      for (final (receive, send) in [...conditions]..shuffle(random)) {
        runs.add(
          base.copyWith(
            runId: newRunId(),
            test: TestKind.latency,
            path: DataPath.rawLsl,
            receiveMode: receive,
            sendMode: send,
            repetition: repetition,
            sweepOrder: runs.length + 1,
          ),
        );
      }
    }
    return runs;
  }
}
