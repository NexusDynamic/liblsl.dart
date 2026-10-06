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

  // --- Shared ---
  final ValueNotifier<int?> _lslver = ValueNotifier(null);
  bool _lslReady = false;

  // --- Producer ---
  final ValueNotifier<double> _elapsedTime = ValueNotifier(0.0);
  final WidgetStatesController _startButtonController = WidgetStatesController({
    WidgetState.disabled,
  });
  double _streamDuration = 5.0; // seconds
  double _sampleRate = 5.0; // Hz
  int _channelCount = 2;
  static const List<double> _sampleRates = [5, 10, 50, 100, 250, 500, 1000];
  static const List<int> _channelCounts = [1, 2, 8, 16, 32];

  // --- Consumer ---
  final ValueNotifier<String?> _streamStatus = ValueNotifier(null);
  final ValueNotifier<String?> _sampleData = ValueNotifier(null);
  List<LSLStreamInfo> _foundStreams = [];
  int _selectedStreamIndex = 0;
  bool _isFindingStreams = false;
  bool _isSampling = false;
  LSLInlet? _activeInlet;
  Timer? _samplingTimer;
  bool _isPulling = false;

  @override
  void initState() {
    super.initState();
    multicastLock
        .acquireMulticastLock()
        .then((_) => debugPrint('acquireMulticastLock: success'))
        .catchError((e) => debugPrint('acquireMulticastLock: error: $e'));
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
                              // Channel count dropdown
                              Row(
                                children: [
                                  Text(
                                    'Channels',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  DropdownButton<int>(
                                    value: _channelCount,
                                    isDense: true,
                                    onChanged: isStreaming
                                        ? null
                                        : (v) {
                                            if (v != null) {
                                              setState(() => _channelCount = v);
                                            }
                                          },
                                    items: _channelCounts
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              '$c ch',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_sampleRate > 100 || _channelCount > 8)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Warning: This app is not optimized for '
                                    'best-performance sample production and is '
                                    'only intended as a demonstration.\nDepending '
                                    'on your hardware, it is possible that the '
                                    'stream will underproduce.\nThere is no risk '
                                    'in running it anyway, it just may not meet '
                                    'the selected sample rate.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                              ElevatedButton(
                                key: const Key('start_streaming'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                ),
                                statesController: _startButtonController,
                                onPressed: _startStream,
                                child: Text(
                                  'Start Stream'
                                  ' (${_sampleRate.toInt()} Hz,'
                                  ' ${_formatDuration(_streamDuration)})',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Note: The first channel of the produced stream'
                                ' will be the sample index.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color:
                                      theme.primaryTextTheme.bodySmall?.color,
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
                      // Find button
                      ElevatedButton(
                        key: const Key('check_streams'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        onPressed:
                            (!_lslReady || _isFindingStreams || _isSampling)
                            ? null
                            : _findStreams,
                        child: Text(
                          _isFindingStreams
                              ? 'Searching...'
                              : 'Find LSL Streams',
                        ),
                      ),
                      // Stream selector + sampling buttons
                      if (_foundStreams.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButton<int>(
                          value: _selectedStreamIndex,
                          isExpanded: true,
                          isDense: true,
                          onChanged: _isSampling
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => _selectedStreamIndex = v);
                                  }
                                },
                          items: _foundStreams
                              .asMap()
                              .entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    '${e.value.streamName}'
                                    '  •  ${e.value.channelCount}ch'
                                    '  •  ${e.value.channelFormat.name}',
                                    key: const Key('resolved_streams'),
                                    style: theme.textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Warning: This app is not optimized for '
                          'best-performance stream sampling, and is relying on '
                          'UI updates to show the sampled data below, please '
                          'bear that in mind if you are sampling from a stream '
                          'with a large number of channels or a high sample rate.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                key: const Key('start_sampling'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                ),
                                onPressed: _isSampling ? null : _startSampling,
                                child: const Text('Start Sampling'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              key: const Key('stop_sampling'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                              ),
                              onPressed: _isSampling ? _stopSampling : null,
                              child: const Text('Stop Sampling'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Status line
                      ValueListenableBuilder<String?>(
                        valueListenable: _streamStatus,
                        builder: (context, status, _) => Text(
                          status ?? 'Status: idle',
                          key: const Key('stream_status'),
                          style: theme.textTheme.bodySmall,
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
    final apiConfig = LSLApiConfig(
      // Here you can specify custom API parameters
      // for liblsl. Including which addresses to bind to.
    );
    LSL.setConfigContent(apiConfig);
    _lslver.value = LSL.version;
    _startButtonController.update(WidgetState.disabled, false);
    setState(() => _lslReady = true);
  }

  static String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toInt()}s';
    final m = secs ~/ 60;
    final s = secs.toInt() % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  // ── Producer ────────────────────────────────────────────────────────────────

  /// Start the stream and update the UI with elapsed time and estimated sample count.
  Future<void> _startStream() async {
    final rate = _sampleRate;
    final durationSecs = _streamDuration.round();
    final channels = _channelCount;
    try {
      _startButtonController.update(WidgetState.disabled, true);
      _elapsedTime.value = 0.0;
      final timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedTime.value += 1.0;
      });
      await _launchStreamIsolate(rate, durationSecs, channels);
      timeTimer.cancel();
      _startButtonController.update(WidgetState.disabled, false);
    } catch (e) {
      debugPrint('Error: $e');
      _startButtonController.update(WidgetState.disabled, false);
    }
  }

  /// Launches the isolate that produces samples
  static Future<int> _launchStreamIsolate(
    double rate,
    int durationSecs,
    int channels,
  ) {
    return Isolate.run(
      () => _streamProducer((
        rate: rate,
        durationSecs: durationSecs,
        channels: channels,
      )),
      debugName: 'LSLTestAppStreamProducer',
    );
  }

  /// Produce a stream with the given parameters.
  /// The first channel of the stream is a sample index, and the rest are random values.
  /// Returns the total number of samples sent.
  static Future<int> _streamProducer(
    ({double rate, int durationSecs, int channels}) params,
  ) async {
    final rate = params.rate;
    final durationSecs = params.durationSecs;
    final channels = params.channels;
    double sentSamples = 0.0;
    // generate 5 char random suffix for stream name and source id to avoid conflicts with
    // another instance of the test app
    final String randomSuffix = Random()
        .nextInt(100000)
        .toString()
        .padLeft(5, '0');
    final String randomDeviceId = 'ASourceDevice_$randomSuffix';
    final String randomStreamName = 'LSLFlutterTest_$randomSuffix';
    // Sample rate
    final intervalMicros = (Duration(seconds: 1).inMicroseconds / rate).round();
    final completer = Completer<void>();
    final streamInfo = await LSL.createStreamInfo(
      streamName: randomStreamName,
      channelCount: channels,
      channelFormat: LSLChannelFormat.float32,
      sampleRate: rate,
      streamType: LSLContentType.eeg,
      sourceId: randomDeviceId,
    );
    final outlet = await LSL.createOutlet(
      streamInfo: streamInfo,
      chunkSize: 1,
      maxBuffer: 10,
      useIsolates: false,
    );
    final rng = Random();
    final randomChannels = streamInfo.channelCount - 1;
    Timer(Duration(seconds: durationSecs), () {
      if (!completer.isCompleted) completer.complete();
    });
    final sample = List<double>.filled(
      streamInfo.channelCount,
      0.0,
      growable: false,
    );
    final Stopwatch stopwatch = Stopwatch()..start();
    int lastSample = 0;
    while (!completer.isCompleted) {
      lastSample = stopwatch.elapsedMicroseconds;
      sample[0] = sentSamples;

      if (randomChannels > 0) {
        for (int i = 1; i < streamInfo.channelCount; i++) {
          sample[i] = rng.nextDouble();
        }
      }

      final result = outlet.pushSampleSync(sample);
      if (result != 0) debugPrint('Error pushing sample: $result');
      sentSamples++;
      final elapsed = stopwatch.elapsedMicroseconds - lastSample;
      final delay = intervalMicros - elapsed;
      if (delay > 0) {
        await Future.delayed(Duration(microseconds: delay));
      } else {
        // We're behind schedule, no delay, just yield to the event loop.
        await Future.delayed(Duration.zero);
      }
    }
    await outlet.destroy();
    streamInfo.destroy();
    return sentSamples.toInt();
  }

  // ── Consumer ─────────────────────────────────────────────────────────────────

  /// Find LSL streams on the network
  Future<void> _findStreams() async {
    setState(() => _isFindingStreams = true);
    _streamStatus.value = 'Searching for streams (limited to 10)...';
    _sampleData.value = null;

    // Destroy any previously found stream infos.
    for (final s in _foundStreams) {
      s.destroy();
    }
    setState(() {
      _foundStreams = [];
      _selectedStreamIndex = 0;
    });

    try {
      final List<int> addrs =
          await Isolate.run(() async {
            final streams = await LSL.resolveStreams(
              waitTime: 2.0,
              maxStreams: 10,
            );
            return streams.map((s) => s.streamInfo.address).toList();
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('Timeout resolving streams');
              return <int>[];
            },
          );

      if (!mounted) return;

      if (addrs.isEmpty) {
        _streamStatus.value = 'No streams found';
        return;
      }

      final infos = addrs
          .map((a) => LSLStreamInfo.fromStreamInfoAddr(a))
          .toList();
      setState(() {
        _foundStreams = infos;
        _selectedStreamIndex = 0;
      });
      _streamStatus.value = 'Found ${infos.length} stream(s)';
    } catch (e) {
      _streamStatus.value = 'Error: $e';
      debugPrint('Error finding streams: $e');
    } finally {
      if (mounted) setState(() => _isFindingStreams = false);
    }
  }

  Future<void> _startSampling() async {
    if (_foundStreams.isEmpty || _selectedStreamIndex >= _foundStreams.length) {
      return;
    }
    try {
      setState(() => _isSampling = true);
      _streamStatus.value = 'Creating inlet...';
      _activeInlet = await LSL.createInlet(
        streamInfo: _foundStreams[_selectedStreamIndex],
      );
      _streamStatus.value = 'Sampling...';
      _samplingTimer = Timer.periodic(
        Duration(milliseconds: (1000.0 / _sampleRate).round()),
        (_) async {
          if (!_isSampling || _activeInlet == null || _isPulling) return;
          _isPulling = true;
          try {
            final s = await _activeInlet!.pullSample(timeout: 0.0);
            if (!mounted) return;
            if (s.errorCode == 0 && s.data.isNotEmpty) {
              _sampleData.value =
                  'Sample: [${s.data.map((v) => v.toStringAsFixed(4)).join(', ')}]';
            }
          } finally {
            _isPulling = false;
          }
        },
      );
      // immediately flush the inlet
      // to avoid a queue buildup of pending samples.
      await _activeInlet!.flush();
    } catch (e) {
      _streamStatus.value = 'Error: $e';
      debugPrint('Error starting sampling: $e');
      if (mounted) setState(() => _isSampling = false);
    }
  }

  Future<void> _stopSampling() async {
    _samplingTimer?.cancel();
    _samplingTimer = null;
    // Wait for any in-progress pull to finish before destroying the inlet.
    // stop the loop.
    _isSampling = false;
    while (_isPulling) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await _activeInlet?.destroy();
    _activeInlet = null;
    if (mounted) {
      setState(() => _isSampling = false);
      _streamStatus.value = 'Sampling stopped';
    }
  }

  @override
  void dispose() {
    _stopSampling();
    multicastLock.releaseMulticastLock();
    _lslver.dispose();
    _elapsedTime.dispose();
    _startButtonController.dispose();
    _streamStatus.dispose();
    _sampleData.dispose();
    _samplingTimer?.cancel();
    _activeInlet?.destroy();
    for (final s in _foundStreams) {
      s.destroy();
    }
    super.dispose();
  }
}

/// A subtly bordered container used for status/result display areas.
class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
