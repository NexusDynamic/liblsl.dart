import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:liblsl/lsl.dart';
import 'dart:math';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LSLTestApp());
}

class LSLTestApp extends StatelessWidget {
  const LSLTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'liblsl Flutter Test',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(),
      home: const LSLTestPage(),
    );
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
  final WidgetStatesController _checkStreamsButtonController =
      WidgetStatesController({WidgetState.disabled});

  final ValueNotifier<List<String>> _resolvedStreams = ValueNotifier([]);
  final ValueNotifier<String?> _sampleData = ValueNotifier(null);
  final ValueNotifier<String?> _streamStatus = ValueNotifier(null);

  double _streamDuration = 5.0; // seconds
  double _sampleRate = 5.0; // Hz
  static const List<double> _sampleRates = [5, 10, 50, 100, 250, 500, 1000];

  @override
  void initState() {
    super.initState();
    _startButtonController.update(WidgetState.disabled, true);
    _checkStreamsButtonController.update(WidgetState.disabled, true);
    multicastLock
        .acquireMulticastLock()
        .then((_) {
          debugPrint('acquireMulticastLock: success');
        })
        .catchError((e) {
          debugPrint('acquireMulticastLock: error: $e');
        });
    _setupLSL();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('liblsl Flutter Test'),
            ValueListenableBuilder<int?>(
              valueListenable: _lslver,
              builder: (context, version, _) => Text(
                version != null
                    ? 'LSL Version $version'
                    : 'Getting LSL Version...',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Stream Producer ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Stream Producer',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ListenableBuilder(
                        listenable: _startButtonController,
                        builder: (context, _) {
                          final isStreaming = _startButtonController.value
                              .contains(WidgetState.disabled);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Duration slider
                              Row(
                                children: [
                                  Text(
                                    'Duration',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _streamDuration,
                                      min: 5,
                                      max: 300,
                                      divisions: 59,
                                      label: _formatDuration(_streamDuration),
                                      onChanged: isStreaming
                                          ? null
                                          : (v) => setState(
                                              () => _streamDuration = v,
                                            ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      _formatDuration(_streamDuration),
                                      style: theme.textTheme.bodySmall,
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              // Sample rate dropdown
                              Row(
                                children: [
                                  Text(
                                    'Sample rate',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  DropdownButton<double>(
                                    value: _sampleRate,
                                    isDense: true,
                                    onChanged: isStreaming
                                        ? null
                                        : (v) {
                                            if (v != null) {
                                              setState(() => _sampleRate = v);
                                            }
                                          },
                                    items: _sampleRates
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(
                                              '${r.toInt()} Hz',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                key: const Key('start_streaming'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isStreaming
                                      ? theme.colorScheme.surface
                                      : theme.colorScheme.surfaceBright,
                                ),
                                statesController: _startButtonController,
                                onPressed: _startStream,
                                child: Text(
                                  'Start Stream'
                                  ' (${_sampleRate.toInt()} Hz,'
                                  ' ${_formatDuration(_streamDuration)})',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _StatusBox(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _elapsedTime,
                          builder: (context, elapsed, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Elapsed: ${elapsed.toStringAsFixed(0)}s',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Approx. samples sent: ${(elapsed * _sampleRate).round()}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // --- Stream Consumer ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Stream Consumer',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        key: const Key('check_streams'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.surfaceBright,
                        ),
                        statesController: _checkStreamsButtonController,
                        onPressed: _checkStreamsAndSample,
                        child: const Text('Check for Streams and Pull Sample'),
                      ),
                      const SizedBox(height: 12),
                      // Stream status line
                      ValueListenableBuilder<String?>(
                        valueListenable: _streamStatus,
                        builder: (context, status, _) => Text(
                          status ?? 'Status: idle',
                          key: const Key('stream_status'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Resolved streams list
                      ValueListenableBuilder<List<String>>(
                        valueListenable: _resolvedStreams,
                        builder: (context, streams, _) => _StatusBox(
                          minHeight: 64,
                          child: streams.isEmpty
                              ? Text(
                                  'No streams found yet',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.disabledColor,
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Found streams:',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    ...streams.map(
                                      (s) => Text(
                                        s,
                                        key: const Key('resolved_streams'),
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Latest sample
                      ValueListenableBuilder<String?>(
                        valueListenable: _sampleData,
                        builder: (context, sample, _) => _StatusBox(
                          child: Text(
                            sample ?? 'No sample received yet',
                            key: const Key('sample_data'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: sample == null
                                  ? theme.disabledColor
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setupLSL() async {
    final apiConfig = LSLApiConfig(ipv6: IPv6Mode.disable);
    LSL.setConfigContent(apiConfig);
    _lslver.value = LSL.version;
    _startButtonController.update(WidgetState.disabled, false);
    _checkStreamsButtonController.update(WidgetState.disabled, false);
  }

  static String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toInt()}s';
    final m = secs ~/ 60;
    final s = secs.toInt() % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  Future<void> _startStream() async {
    final rate = _sampleRate;
    final durationSecs = _streamDuration.round();
    try {
      _startButtonController.update(WidgetState.disabled, true);
      _elapsedTime.value = 0.0;
      final timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedTime.value += 1.0;
      });
      await _launchStreamIsolate(rate, durationSecs);
      timeTimer.cancel();
      _startButtonController.update(WidgetState.disabled, false);
    } catch (e) {
      debugPrint('Error: $e');
      _startButtonController.update(WidgetState.disabled, false);
    }
  }

  /// Non-async static launcher so the closure passed to [Isolate.run] is
  /// created in a plain synchronous scope. This guarantees the closure only
  /// captures the two primitive arguments — never the async state-machine
  /// context of [_startStream] (which would drag in [ValueNotifier] listeners
  /// and the full Flutter widget tree, causing an "unsendable" isolate error).
  static Future<int> _launchStreamIsolate(double rate, int durationSecs) {
    return Isolate.run(
      () => _streamProducer((rate: rate, durationSecs: durationSecs)),
      debugName: 'LSLTestAppStreamProducer',
    );
  }

  static Future<int> _streamProducer(
    ({double rate, int durationSecs}) params,
  ) async {
    final rate = params.rate;
    final durationSecs = params.durationSecs;
    int sentSamples = 0;
    final intervalMs = (1000.0 / rate).round();
    final completer = Completer<void>();
    final streamInfo = await LSL.createStreamInfo(
      streamName: 'FlutterApp',
      channelCount: 2,
      channelFormat: LSLChannelFormat.float32,
      sampleRate: rate,
      streamType: LSLContentType.eeg,
      sourceId: 'FlutterAppDevice',
    );
    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 1,
      maxBuffer: 10,
      useIsolates: false,
    );
    final rng = Random();
    Timer(Duration(seconds: durationSecs), () {
      if (!completer.isCompleted) completer.complete();
    });
    while (!completer.isCompleted) {
      final sample = List<double>.generate(
        streamInfo.channelCount,
        (index) => rng.nextDouble(),
      );
      final result = await outlet.pushSample(sample);
      if (result != 0) {
        debugPrint('Error pushing sample: $result');
      }
      sentSamples++;
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
    await outlet.destroy();
    streamInfo.destroy();
    return sentSamples;
  }

  Future<void> _checkStreamsAndSample() async {
    try {
      _checkStreamsButtonController.update(WidgetState.disabled, true);
      _streamStatus.value = 'Checking streams...';
      _resolvedStreams.value = [];
      _sampleData.value = null;

      final List<int> streamAddrs =
          await Isolate.run(() async {
            final streams = await LSL.resolveStreamsByProperty(
              property: LSLStreamProperty.sourceId,
              value: 'FlutterAppDevice',
              waitTime: 2.0,
              maxStreams: 1,
            );
            return streams.map((s) => s.streamInfo.address).toList();
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('Timeout while resolving streams');
              return <int>[];
            },
          );

      if (streamAddrs.isEmpty) {
        _streamStatus.value = 'No streams found';
        return;
      }

      final streams = streamAddrs
          .map((addr) => LSLStreamInfo.fromStreamInfoAddr(addr))
          .toList();

      _resolvedStreams.value = streams
          .map(
            (s) =>
                '${s.streamName}  •  ${s.channelCount}ch  •  ${s.channelFormat.name}',
          )
          .toList();
      _streamStatus.value = 'Found ${streams.length} stream(s)';

      if (streams.isNotEmpty) {
        final stream = streams[0];
        if (stream.streamName == 'FlutterApp' &&
            stream.channelCount == 2 &&
            stream.channelFormat == LSLChannelFormat.float32) {
          _streamStatus.value = 'Creating inlet...';
          final inlet = await LSL.createInlet(streamInfo: stream);

          if (inlet.streamInfo.streamName == 'FlutterApp') {
            _streamStatus.value = 'Pulling sample...';
            final sample = await inlet.pullSample(timeout: 1.0);

            if (sample.errorCode == 0 && sample.data.length == 2) {
              _sampleData.value =
                  'Sample: [${sample.data[0].toStringAsFixed(4)}, '
                  '${sample.data[1].toStringAsFixed(4)}]';
              _streamStatus.value = 'Sample received successfully!';
            } else {
              _sampleData.value = 'Error code: ${sample.errorCode}';
              _streamStatus.value = 'Failed to receive sample';
            }
          }

          await inlet.destroy();
        } else {
          _streamStatus.value = "Stream properties don't match";
        }
      }

      streams.destroy();
    } catch (e) {
      _streamStatus.value = 'Error: $e';
      debugPrint('Error checking streams: $e');
    } finally {
      _checkStreamsButtonController.update(WidgetState.disabled, false);
    }
  }

  @override
  void dispose() {
    multicastLock.releaseMulticastLock();
    _lslver.dispose();
    _elapsedTime.dispose();
    _startButtonController.dispose();
    _checkStreamsButtonController.dispose();
    _resolvedStreams.dispose();
    _sampleData.dispose();
    _streamStatus.dispose();
    super.dispose();
  }
}

/// A subtly bordered container used for status/result display areas.
class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.child, this.minHeight = 48});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
