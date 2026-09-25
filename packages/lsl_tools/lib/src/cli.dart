import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:signal_core/signal_core.dart';
import 'package:xdf/xdf.dart';
import 'package:xml/xml.dart';

import 'bridge/client.dart';
import 'bridge/protocol.dart';
import 'bridge/server.dart';
import 'lsl.dart';
import 'lsl_recorder.dart';
import 'lsl_test_outlets.dart';

/// Run the `lsl` command line tool with [args]; returns the exit code.
/// [stop] ends long-running commands (default: Ctrl-C).
Future<int> runLslCli(
  List<String> args, {
  Future<void>? stop,
  StringSink? out,
}) async {
  final o = out ?? stdout;
  final runner =
      CommandRunner<int>(
          'lsl',
          'Lab Streaming Layer from the command line: list, record, share and '
              'bridge streams.',
        )
        ..argParser.addMultiOption(
          'peer',
          help:
              'Address of a computer to look for streams on, where multicast '
              'does not reach (repeat for more).',
        );
  for (final c in <Command<int>>[
    _List(o),
    _Info(o),
    _Record(o, stop),
    _Share(o, stop),
    _Bridge(o, stop),
    _Generate(o, stop),
    _Replay(o, stop),
  ]) {
    runner.addCommand(c);
  }
  try {
    final parsed = runner.parse(args);
    final peers = parsed['peer'] as List<String>;
    if (peers.isNotEmpty) {
      lsl.configure(LslNetworkOptions(knownPeers: peers));
    }
    return await runner.runCommand(parsed) ?? 0;
  } on UsageException catch (e) {
    o.writeln(e);
    return 64;
  } finally {
    _discovery?.close();
    _discovery = null;
  }
}

/// Completes on Ctrl-C (or SIGTERM), or on [stop].
Future<void> _untilStopped(Future<void>? stop) {
  if (stop != null) return stop;
  final done = Completer<void>();
  late final StreamSubscription<ProcessSignal> a;
  StreamSubscription<ProcessSignal>? b;
  void finish(ProcessSignal _) {
    a.cancel();
    b?.cancel();
    if (!done.isCompleted) done.complete();
  }

  a = ProcessSignal.sigint.watch().listen(finish);
  if (!Platform.isWindows) b = ProcessSignal.sigterm.watch().listen(finish);
  return done.future;
}

/// Where commands look for streams; open while they run, since the
/// streams it found can only be opened while it is.
LslDiscovery? _discovery;

/// Streams on the network after [wait], matching [patterns] (by name or
/// type, `*` as a wildcard; all without patterns).
Future<List<LslStreamDescription>> _find(
  List<String> patterns, {
  Duration wait = const Duration(seconds: 2),
}) async {
  await lsl.prepare();
  final d = _discovery ??= lsl.discover();
  await Future<void>.delayed(wait);
  final all = await d.streams();
  all.sort((a, b) => a.name.compareTo(b.name));
  if (patterns.isEmpty) return all;
  bool matches(String p, String s) => RegExp(
    '^${RegExp.escape(p).replaceAll(r'\*', '.*')}\$',
    caseSensitive: false,
  ).hasMatch(s);
  return [
    for (final s in all)
      if (patterns.any((p) => matches(p, s.name) || matches(p, s.type))) s,
  ];
}

String _rate(double r) => r > 0
    ? '${r == r.roundToDouble() ? r.toStringAsFixed(0) : r} Hz'
    : 'irregular';

String _duration(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

abstract class _Base extends Command<int> {
  final StringSink out;
  _Base(this.out);

  void streamOption() => argParser.addMultiOption(
    'stream',
    abbr: 's',
    help: 'Streams by name or type (* matches anything); all without.',
  );

  List<String> get patterns => argResults!['stream'] as List<String>;
}

class _List extends _Base {
  _List(super.out) {
    argParser.addOption('wait', defaultsTo: '2', help: 'Seconds to look.');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List the streams on the network.';

  @override
  Future<int> run() async {
    final wait = double.tryParse(argResults!['wait'] as String) ?? 2;
    final streams = await _find(
      const [],
      wait: Duration(milliseconds: (wait * 1000).round()),
    );
    if (streams.isEmpty) {
      out.writeln('No streams found.');
      return 1;
    }
    for (final s in streams) {
      out.writeln(
        '${s.name}\t${s.type}\t${s.channelCount} ch\t${_rate(s.rate)}\t'
        '${s.format.name}\t${s.hostname}\t${s.sourceId}',
      );
    }
    return 0;
  }
}

class _Info extends _Base {
  _Info(super.out);

  @override
  String get name => 'info';

  @override
  String get description =>
      'Show a stream\'s full info (XML) and clock offset.';

  @override
  String get invocation => 'lsl info <name or type>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('Which stream?');
    final found = await _find(rest);
    if (found.isEmpty) {
      out.writeln('No stream matches ${rest.join(' ')}.');
      return 1;
    }
    for (final s in found) {
      final inlet = await lsl.openInlet(
        s,
        const LslInletOptions(clockSync: false, dejitter: false),
      );
      try {
        final xml = inlet.fullXml.isNotEmpty ? inlet.fullXml : s.xml;
        try {
          out.writeln(XmlDocument.parse(xml).toXmlString(pretty: true));
        } catch (_) {
          out.writeln(xml);
        }
        final offset = await inlet.timeCorrection();
        out.writeln('clock offset: ${(offset * 1000).toStringAsFixed(3)} ms');
      } finally {
        await inlet.close();
      }
    }
    return 0;
  }
}

class _Record extends _Base {
  final Future<void>? stop;
  _Record(super.out, this.stop) {
    streamOption();
    argParser.addOption(
      'duration',
      abbr: 'd',
      help: 'Seconds to record; until Ctrl-C without.',
    );
  }

  @override
  String get name => 'record';

  @override
  String get description =>
      'Record streams to an XDF file, as LabRecorder does.';

  @override
  String get invocation => 'lsl record <file.xdf> [-s stream]...';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('One file to record to.');
    final streams = await _find(patterns);
    if (streams.isEmpty) {
      out.writeln('No streams to record.');
      return 1;
    }
    final file = File(rest.single);
    final recorder = await LslRecorder.start(
      streams,
      file.openWrite(),
      where: file.path,
    );
    out.writeln(
      'Recording ${streams.map((s) => s.name).join(', ')} to ${file.path}',
    );
    final seconds = double.tryParse(argResults!['duration'] as String? ?? '');
    final progress = Timer.periodic(const Duration(seconds: 5), (_) {
      out.writeln(
        '${_duration(recorder.elapsed)}  ${recorder.sampleCount} samples',
      );
    });
    await Future.any([
      _untilStopped(stop),
      if (seconds != null)
        Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round())),
    ]);
    progress.cancel();
    await recorder.stop();
    for (final s in recorder.streams) {
      out.writeln(
        '${s.stream.name}: ${s.samples} samples'
        '${s.error == null ? '' : ' (stopped: ${s.error})'}',
      );
    }
    return 0;
  }
}

class _Share extends _Base {
  final Future<void>? stop;
  _Share(super.out, this.stop) {
    streamOption();
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: '8765')
      ..addOption('token', help: 'Clients must give it to connect.');
  }

  @override
  String get name => 'share';

  @override
  String get description =>
      'Share streams over a WebSocket, for `lsl bridge` or the viewer on '
      'other networks.';

  @override
  Future<int> run() async {
    final streams = await _find(patterns);
    if (streams.isEmpty) {
      out.writeln('No streams to share.');
      return 1;
    }
    final server = await LslBridgeServer.start(
      streams,
      port: int.tryParse(argResults!['port'] as String) ?? 8765,
      token: argResults!['token'] as String? ?? '',
    );
    out.writeln(
      'Sharing ${streams.map((s) => s.name).join(', ')} on port '
      '${server.port}',
    );
    await _untilStopped(stop);
    await server.close();
    return 0;
  }
}

class _Bridge extends _Base {
  final Future<void>? stop;
  _Bridge(super.out, this.stop) {
    streamOption();
    argParser
      ..addOption('token')
      ..addOption(
        'suffix',
        defaultsTo: '',
        help: 'Added to the names of the streams published here.',
      );
  }

  @override
  String get name => 'bridge';

  @override
  String get description =>
      'Receive the streams a bridge (`lsl share`, or the viewer) shares and '
      'publish them here as LSL streams.';

  @override
  String get invocation => 'lsl bridge ws://host:8765 [-s stream]...';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('The bridge\'s address.');
    var text = rest.single;
    if (!text.contains('://')) text = 'ws://$text';
    final client = await LslBridgeClient.connect(
      Uri.parse(text),
      token: argResults!['token'] as String? ?? '',
    );
    if (client.streams.isEmpty) {
      await client.onStreams.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const [],
      );
    }
    bool wanted(BridgeStream s) =>
        patterns.isEmpty ||
        patterns.any(
          (p) => RegExp(
            '^${RegExp.escape(p).replaceAll(r'\*', '.*')}\$',
            caseSensitive: false,
          ).hasMatch(s.description.name),
        );
    final suffix = argResults!['suffix'] as String;
    await lsl.prepare();
    final relays = <(LslInlet, LslOutlet)>[];
    for (final s in client.streams.where(wanted)) {
      final d = s.description;
      final outlet = await lsl.createOutlet(
        LslOutletSpec(
          name: '${d.name}$suffix',
          type: d.type,
          channelCount: d.format.isString ? 1 : d.channelCount,
          rate: d.rate,
          format: d.format.isString ? LslFormat.string : LslFormat.float32,
          sourceId: 'bridge:${d.sourceId.isEmpty ? d.name : d.sourceId}',
          channels: s.channels,
        ),
        const LslOutletOptions(),
      );
      relays.add((client.open(s), outlet));
      out.writeln('Publishing ${d.name}$suffix');
    }
    if (relays.isEmpty) {
      out.writeln('The bridge shares no matching streams.');
      await client.close();
      return 1;
    }
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) async {
      for (final (inlet, outlet) in relays) {
        final c = await inlet.pull(4096);
        if (c.length == 0) continue;
        if (c.strings != null) {
          final ch = inlet.stream.channelCount;
          await outlet.pushStrings([
            for (var i = 0; i < c.length; i++) c.strings![i * ch],
          ], c.times);
        } else {
          await outlet.push(
            c.values is Float32List
                ? c.values! as Float32List
                : Float32List.fromList(c.values!),
            c.times,
          );
        }
      }
    });
    await Future.any([
      _untilStopped(stop),
      Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return !client.closed;
      }),
    ]);
    timer.cancel();
    if (client.closed) out.writeln('The bridge closed: ${client.error}');
    for (final (inlet, outlet) in relays) {
      await inlet.close();
      await outlet.close();
    }
    await client.close();
    return 0;
  }
}

class _Generate extends _Base {
  final Future<void>? stop;
  _Generate(super.out, this.stop) {
    argParser
      ..addOption('name', defaultsTo: 'Test signal')
      ..addOption('type', defaultsTo: 'EEG')
      ..addOption('channels', abbr: 'c', defaultsTo: '8')
      ..addOption('rate', abbr: 'r', defaultsTo: '250')
      ..addOption('frequency', abbr: 'f', defaultsTo: '10');
  }

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Send a test stream: sines (channel n at n × the frequency) and '
      'noise.';

  @override
  Future<int> run() async {
    double num(String k) => double.parse(argResults![k] as String);
    final g = await LslSignalGenerator.start(
      name: argResults!['name'] as String,
      type: argResults!['type'] as String,
      channels: num('channels').round(),
      rate: num('rate'),
      frequency: num('frequency'),
    );
    out.writeln('Sending ${g.name}; Ctrl-C to stop');
    await _untilStopped(stop);
    await g.close();
    out.writeln('Sent ${g.sent} samples');
    return 0;
  }
}

class _Replay extends _Base {
  final Future<void>? stop;
  _Replay(super.out, this.stop) {
    argParser.addFlag('loop', help: 'Start again at the end.');
  }

  @override
  String get name => 'replay';

  @override
  String get description =>
      'Play an XDF recording as LSL streams, in real time.';

  @override
  String get invocation => 'lsl replay <file.xdf> [--loop]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('One XDF file.');
    final file = await XdfFile.open(ByteSource.path(rest.single));
    await file.indexed;
    await lsl.prepare();
    final outlets = <LslOutlet>[];
    for (final s in file.streams) {
      final i = s.info;
      outlets.add(
        await lsl.createOutlet(
          LslOutletSpec(
            name: i.name,
            type: i.type,
            channelCount: i.format.isString ? 1 : i.channelCount,
            rate: s.regular ? i.nominalRate : 0,
            format: i.format.isString ? LslFormat.string : LslFormat.float32,
            sourceId: 'replay:${i.sourceId.isEmpty ? i.name : i.sourceId}',
            channels: [
              for (var c = 0; c < (i.format.isString ? 1 : i.channelCount); c++)
                LslChannel(i.label(c), unit: i.unit(c)),
            ],
          ),
          const LslOutletOptions(),
        ),
      );
    }
    out.writeln(
      'Replaying ${file.streams.length} streams '
      '(${file.duration.toStringAsFixed(1)} s)',
    );
    final loop = argResults!['loop'] as bool;
    final stopped = _untilStopped(stop);
    var done = false;
    unawaited(stopped.then((_) => done = true));
    do {
      await _play(file, outlets, () => done);
    } while (loop && !done);
    for (final o in outlets) {
      await o.close();
    }
    await file.close();
    return 0;
  }

  /// Send the whole file once, in real time.
  Future<void> _play(
    XdfFile file,
    List<LslOutlet> outlets,
    bool Function() stopped,
  ) async {
    final start = lsl.clock();
    final pushed = [for (final _ in file.streams) 0.0];
    final nextEvent = [for (final _ in file.streams) 0];
    const block = 0.05;
    for (var t = 0.0; t < file.duration + block && !stopped(); t += block) {
      final wait = start + t - lsl.clock();
      if (wait > 0) {
        await Future<void>.delayed(
          Duration(microseconds: (wait * 1e6).round()),
        );
      }
      for (final s in file.streams) {
        final o = outlets[s.slot];
        if (s.regular) {
          final from = math.max(pushed[s.slot], s.t0);
          final to = math.min(t + block, s.t1);
          if (to <= from) continue;
          final w = await file.read(
            ReadRequest(
              channels: [
                for (var c = 0; c < s.channelCount; c++) ChannelRef(s.slot, c),
              ],
              t0: from,
              t1: to,
            ),
          );
          pushed[s.slot] = to;
          final n = w.length;
          if (n == 0) continue;
          final ch = s.channelCount;
          final values = Float32List(n * ch);
          final times = Float64List(n);
          var k = 0;
          for (var i = 0; i < n; i++) {
            if (w.channels[0][i].isNaN) continue;
            for (var c = 0; c < ch; c++) {
              values[k * ch + c] = w.channels[c][i];
            }
            times[k++] = start + w.start + i / w.samplingRate;
          }
          if (k > 0) {
            await o.push(
              Float32List.sublistView(values, 0, k * ch),
              Float64List.sublistView(times, 0, k),
            );
          }
        } else {
          final e = file.events(s.slot);
          final times = <double>[];
          final strings = <String>[];
          final values = <double>[];
          while (nextEvent[s.slot] < e.length &&
              e.times[nextEvent[s.slot]] < t + block) {
            final i = nextEvent[s.slot]++;
            times.add(start + e.times[i]);
            if (e.strings != null) {
              strings.add(e.strings![0][i]);
            } else {
              for (final c in e.channels) {
                values.add(c[i]);
              }
            }
          }
          if (times.isEmpty) continue;
          if (e.strings != null) {
            await o.pushStrings(strings, times);
          } else {
            await o.push(
              Float32List.fromList(values),
              Float64List.fromList(times),
            );
          }
        }
      }
    }
  }
}
