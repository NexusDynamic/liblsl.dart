import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:openbci_cyton/xdf.dart';
import 'package:serial_transport/serial_transport.dart';
import 'package:signal_core/signal_core.dart';
import 'package:xdf/xdf.dart';
import 'package:xml/xml.dart';

import 'bridge/client.dart';
import 'bridge/republisher.dart';
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
    _Share(o, stop, relay: true),
    _Bridge(o, stop),
    _Publish(o, stop),
    _Generate(o, stop),
    _Replay(o, stop),
    _Cyton(o, stop),
    _CytonSd(o),
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

  /// `lsl relay`: `lsl share --relay`.
  final bool relay;

  _Share(super.out, this.stop, {this.relay = false}) {
    if (!relay) streamOption();
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: '8765')
      ..addOption(
        'host',
        defaultsTo: '0.0.0.0',
        help: 'Address to listen on (127.0.0.1: this computer only).',
      )
      ..addOption('token', help: 'Clients must give it to connect.')
      ..addMultiOption(
        'allow-origin',
        help:
            'Only accept browsers on pages from this origin, e.g. '
            'https://example.org (repeat for more; any without).',
      );
    if (!relay) {
      argParser
        ..addFlag(
          'accept',
          help:
              'Let clients publish streams here (e.g. a browser reading a '
              'serial device or replaying a recording): each is shared with '
              'the other clients and becomes an LSL stream on this computer.',
        )
        ..addFlag(
          'relay',
          help:
              'Only relay streams between clients: --accept without LSL '
              'outlets here and without sharing local streams. Needs no LSL '
              'network, e.g. on a server.',
        )
        ..addFlag(
          'local-outlets',
          defaultsTo: true,
          help: 'With --accept, also publish clients\' streams as LSL here.',
        )
        ..addOption(
          'rescan',
          help:
              'Look for new matching streams every this many seconds and '
              'share them too.',
        );
    }
  }

  @override
  String get name => relay ? 'relay' : 'share';

  @override
  String get description => relay
      ? 'Relay streams between WebSocket clients (browsers, viewers, `lsl '
            'bridge`): what one publishes, the others receive. Needs no LSL.'
      : 'Share streams over a WebSocket, for `lsl bridge` or the viewer on '
            'other networks.';

  bool _flag(String name) =>
      argParser.options.containsKey(name) && argResults![name] as bool;

  @override
  Future<int> run() async {
    final relayOnly = relay || _flag('relay');
    final accept = relayOnly || _flag('accept');
    final local = !relayOnly && (argResults!['local-outlets'] as bool? ?? true);
    final pats = relayOnly ? const <String>[] : patterns;
    // Only accepting: share nothing unless streams are named.
    final streams = accept && pats.isEmpty
        ? const <LslStreamDescription>[]
        : await _find(pats);
    if (streams.isEmpty && !accept) {
      out.writeln('No streams to share.');
      return 1;
    }
    final server = await LslBridgeServer.start(
      streams,
      port: int.tryParse(argResults!['port'] as String) ?? 8765,
      host: argResults!['host'] as String,
      token: argResults!['token'] as String? ?? '',
      acceptPublish: accept,
      localOutlets: local,
      allowedOrigins: argResults!['allow-origin'] as List<String>,
    );
    final what = relayOnly
        ? 'Relaying streams between clients'
        : 'Sharing ${streams.isEmpty ? 'no streams' : streams.map((s) => s.name).join(', ')}'
              '${accept ? ', accepting published streams,' : ''}';
    out.writeln('$what on port ${server.port} (address ${server.host})');
    final changes = server.onChange.listen((_) {
      out.writeln(
        '${server.clientCount} connected; published: '
        '${server.published.isEmpty ? 'none' : server.published.join(', ')}',
      );
    });
    Timer? rescan;
    final every = double.tryParse(
      argParser.options.containsKey('rescan')
          ? argResults!['rescan'] as String? ?? ''
          : '',
    );
    if (every != null && every > 0 && !relayOnly) {
      var scanning = false;
      rescan = Timer.periodic(Duration(milliseconds: (every * 1000).round()), (
        _,
      ) async {
        if (scanning) return;
        scanning = true;
        try {
          for (final s in await _find(pats, wait: Duration.zero)) {
            if (await server.share(s)) out.writeln('Sharing ${s.name}');
          }
        } catch (e) {
          out.writeln('Could not look for streams: $e');
        } finally {
          scanning = false;
        }
      });
    }
    await _untilStopped(stop);
    rescan?.cancel();
    await changes.cancel();
    await server.close();
    return 0;
  }
}

/// One line for a stream's [chain]: the totals, then what each hop added.
String _timing(ClockChain chain) {
  String ms(double? s) => s == null ? '?' : (s * 1000).toStringAsFixed(2);
  final hops = <String>[];
  double? before = 0;
  for (final h in chain.hops) {
    final added = h.latency == null || before == null
        ? null
        : h.latency! - before;
    hops.add(
      '${h.via} to ${h.node} ±${ms(h.uncertainty / 2)}, '
      'latency +${ms(added)} (jitter ${ms(h.jitter)})'
      '${h.held == null ? '' : ', held ${ms(h.held)}'}',
    );
    before = h.latency;
  }
  return 'offset ${ms(chain.offset)} ms ±${ms(chain.uncertainty / 2)}, '
      'drift ${(chain.drift * 1e6).toStringAsFixed(1)} ppm, '
      'latency ${ms(chain.latency)} ms [${hops.join('; ')}]';
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
      )
      ..addFlag(
        'timing-stream',
        defaultsTo: true,
        help:
            'Also publish a "BridgeTiming" stream: every two seconds, each '
            'stream\'s clock offset, error bound, drift and latency, hop by '
            'hop, as JSON.',
      )
      ..addOption(
        'stats',
        help: 'Print the same timing every this many seconds.',
      );
  }

  @override
  String get name => 'bridge';

  @override
  String get description =>
      'Receive the streams a bridge or relay (`lsl share`, `lsl relay`, or '
      'the viewer) shares and publish them here as LSL streams, following '
      'streams as they come and go.';

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
      name: Platform.localHostname,
    );
    if (client.streams.isEmpty) {
      await client.onStreams.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const [],
      );
    }
    final republisher = await LslBridgeRepublisher.start(
      client,
      patterns: patterns,
      suffix: argResults!['suffix'] as String,
      timingStream: argResults!['timing-stream'] as bool,
    );
    final every = double.tryParse(argResults!['stats'] as String? ?? '');
    final stats = every == null || every <= 0
        ? null
        : Timer.periodic(Duration(milliseconds: (every * 1000).round()), (_) {
            for (final MapEntry(key: name, value: chain)
                in republisher.timing.entries) {
              out.writeln('$name: ${_timing(chain)}');
            }
          });
    var shown = <String>{};
    void report() {
      final now = republisher.names.toSet();
      for (final n in now.difference(shown)) {
        out.writeln('Publishing $n');
      }
      for (final n in shown.difference(now)) {
        out.writeln('Stopped $n');
      }
      shown = now;
    }

    report();
    final changes = republisher.onChange.listen((_) => report());
    if (shown.isEmpty) {
      out.writeln('The bridge shares no matching streams yet; waiting.');
    }
    await Future.any([
      _untilStopped(stop),
      Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return !client.closed;
      }),
    ]);
    stats?.cancel();
    if (client.closed) out.writeln('The bridge closed: ${client.error}');
    await changes.cancel();
    await republisher.close();
    await client.close();
    return 0;
  }
}

class _Publish extends _Base {
  final Future<void>? stop;
  _Publish(super.out, this.stop) {
    streamOption();
    argParser
      ..addOption('token')
      ..addOption(
        'rescan',
        help:
            'Look for new matching streams every this many seconds and '
            'publish them too.',
      );
  }

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish streams from here on a bridge or relay (`lsl share --accept`, '
      '`lsl relay`), e.g. from a lab behind a firewall to a relay on a '
      'server.';

  @override
  String get invocation => 'lsl publish ws://host:8765 [-s stream]...';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('The bridge\'s address.');
    var text = rest.single;
    if (!text.contains('://')) text = 'ws://$text';
    final client = await LslBridgeClient.connect(
      Uri.parse(text),
      token: argResults!['token'] as String? ?? '',
      name: Platform.localHostname,
    );
    if (client.streams.isEmpty) {
      await client.onStreams.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const [],
      );
    }
    if (!client.acceptsPublish) {
      out.writeln('The bridge does not accept streams (use --accept there).');
      await client.close();
      return 1;
    }
    // Published stream by uid: its inlet here and outlet there.
    final relays = <String, (LslInlet, BridgeOutlet)>{};
    Future<void> measure(LslInlet inlet, BridgeOutlet outlet) async {
      try {
        outlet.upstream = await inlet.chain();
      } catch (_) {
        // No measurement now; the bridge keeps the last.
      }
    }

    Future<void> add(List<LslStreamDescription> found) async {
      for (final s in found) {
        // Skip what came from a bridge, which would go round in circles.
        if (relays.containsKey(s.uid) || s.sourceId.startsWith('bridge:')) {
          continue;
        }
        // Time stamps as the sender gave them, passed on with what LSL
        // measures of its clock.
        final inlet = await lsl.openInlet(
          s,
          const LslInletOptions(clockSync: false, dejitter: false),
        );
        final outlet = await client.publish(
          LslOutletSpec(
            name: s.name,
            type: s.type,
            channelCount: s.channelCount,
            rate: s.rate,
            format: s.format.outletFormat,
            sourceId: s.sourceId,
            channels: inlet.channels,
          ),
        );
        relays[s.uid] = (inlet, outlet);
        await measure(inlet, outlet);
        out.writeln('Publishing ${s.name}');
      }
    }

    await add(await _find(patterns));
    if (relays.isEmpty) out.writeln('No matching streams yet.');
    final every = double.tryParse(argResults!['rescan'] as String? ?? '');
    var scanning = false;
    final rescan = every == null || every <= 0
        ? null
        : Timer.periodic(Duration(milliseconds: (every * 1000).round()), (
            _,
          ) async {
            if (scanning) return;
            scanning = true;
            try {
              await add(await _find(patterns, wait: Duration.zero));
            } catch (e) {
              out.writeln('Could not publish: $e');
            } finally {
              scanning = false;
            }
          });
    if (relays.isEmpty && rescan == null) {
      await client.close();
      return 1;
    }
    // As often as LSL measures clock offsets.
    final measuring = Timer.periodic(const Duration(seconds: 2), (_) {
      for (final (inlet, outlet) in [...relays.values]) {
        measure(inlet, outlet);
      }
    });
    var pulling = false;
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) async {
      if (pulling) return;
      pulling = true;
      try {
        for (final (inlet, outlet) in [...relays.values]) {
          // Not before the bridge can be told how to read the time stamps.
          if (outlet.upstream.hops.isEmpty) continue;
          final c = await inlet.pull(4096);
          if (c.length == 0) continue;
          if (c.strings != null) {
            await outlet.pushStrings(c.strings!, c.times);
          } else {
            await outlet.push(
              c.typed ?? Float64List.fromList(c.values!),
              c.times,
            );
          }
        }
      } catch (_) {
        // A stream went away; the others go on.
      } finally {
        pulling = false;
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
    measuring.cancel();
    rescan?.cancel();
    if (client.closed) out.writeln('The bridge closed: ${client.error}');
    for (final (inlet, outlet) in relays.values) {
      await outlet.close();
      await inlet.close();
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
            // As recorded: the same format, every channel.
            channelCount: i.channelCount,
            rate: s.regular ? i.nominalRate : 0,
            format: i.format.outletFormat,
            sourceId: 'replay:${i.sourceId.isEmpty ? i.name : i.sourceId}',
            channels: [
              for (var c = 0; c < i.channelCount; c++)
                LSLChannel(i.label(c), unit: i.unit(c)),
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

  /// Send the whole file once, in real time, exactly as recorded.
  Future<void> _play(
    XdfFile file,
    List<LslOutlet> outlets,
    bool Function() stopped,
  ) async {
    final start = lsl.clock();
    const block = 0.05, ahead = 1.0;
    // Per stream: samples read ahead, the next of them to send, and up to
    // when they were read.
    final read = [for (final _ in file.streams) LslChunk.empty];
    final next = [for (final _ in file.streams) 0];
    final readTo = [for (final _ in file.streams) 0.0];
    for (var t = 0.0; t < file.duration + block && !stopped(); t += block) {
      final wait = start + t - lsl.clock();
      if (wait > 0) {
        await Future<void>.delayed(
          Duration(microseconds: (wait * 1e6).round()),
        );
      }
      for (final s in file.streams) {
        final k = s.slot;
        if (next[k] >= read[k].length && readTo[k] < t + block) {
          read[k] = await file.exactSamples(k, readTo[k], readTo[k] + ahead);
          next[k] = 0;
          readTo[k] += ahead;
        }
        final c = read[k];
        final a = next[k];
        var z = a;
        while (z < c.length && c.times[z] < t + block) {
          z++;
        }
        if (z == a) continue;
        next[k] = z;
        final times = Float64List(z - a);
        for (var i = a; i < z; i++) {
          times[i - a] = start + c.times[i];
        }
        final ch = s.channelCount;
        final o = outlets[k];
        if (c.strings != null) {
          await o.pushStrings(c.strings!.sublist(a * ch, z * ch), times);
        } else {
          final data = c.typed ?? Float64List.fromList(c.values!);
          await o.push(sliceTyped(data, a * ch, z * ch), times);
        }
      }
    }
  }
}

/// The UltraCortex Mark IV's electrodes, in channel order.
const _ultracortex = [
  'Fp1', 'Fp2', 'C3', 'C4', 'P7', 'P8', 'O1', 'O2', //
  'F7', 'F8', 'F3', 'F4', 'T7', 'T8', 'P3', 'P4',
];

/// Channels (1-[n]) given as a multi-option, e.g. `--emg 9 --emg 10` or
/// `--emg 9,10`.
Set<int> _channels(List<String> values, int n) {
  final out = <int>{};
  for (final v in values.expand((v) => v.split(','))) {
    final c = int.tryParse(v.trim());
    if (c == null || c < 1 || c > 16) {
      throw UsageException('Not a channel (1-16): $v', '');
    }
    if (c <= n) out.add(c);
  }
  return out;
}

class _Cyton extends _Base {
  final Future<void>? stop;
  _Cyton(super.out, this.stop) {
    argParser
      ..addOption('name', defaultsTo: 'OpenBCI Cyton')
      ..addFlag('daisy', defaultsTo: true, help: 'Use a Daisy if there is one.')
      ..addFlag(
        'ultracortex',
        defaultsTo: true,
        help: 'Name channels as the UltraCortex Mark IV electrodes.',
      )
      ..addOption(
        'gain',
        allowed: [for (final g in cytonGains) '$g'],
        defaultsTo: '24',
        help: 'Gain of all channels.',
      )
      ..addMultiOption(
        'bipolar',
        help: 'Channels (1-16) without the SRB2 reference.',
      )
      ..addMultiOption(
        'emg',
        help:
            'Channels (1-16) used for EMG: bipolar, and published as a '
            'stream of their own.',
      )
      ..addFlag(
        'markers',
        negatable: false,
        help:
            'The marker board mode (no accelerometer): markers typed on '
            'standard input, one a line (128-239, or one of '
            '$cytonSafeMarkerChars), go into the samples (and an SD card '
            'recording) and are published as a markers stream.',
      )
      ..addOption(
        'sd',
        valueHelp: 'minutes',
        help: 'Also record to the SD card, with room for this long.',
      )
      ..addOption(
        'sd-rate',
        allowed: [for (final r in CytonSampleRate.values) '${r.hz}'],
        defaultsTo: '250',
        help:
            'Sampling rate of the SD card recording. Above 250 Hz the board '
            'does not stream, and nothing is published.',
      );
  }

  @override
  String get name => 'cyton';

  @override
  String get description =>
      'Publish an OpenBCI Cyton (+ Daisy) as LSL streams: EEG (µV), EMG, '
      'and the accelerometer (g) or markers; optionally record to its SD '
      'card. Without a port, list the serial ports.';

  @override
  String get invocation => 'lsl cyton [<serial port>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final serial = SerialPortProvider.platform();
    final rest = args.rest;
    if (rest.isEmpty) {
      for (final p in await serial.listPorts()) {
        out.writeln('${p.id}\t${p.description}');
      }
      return 0;
    }
    final sdText = args['sd'] as String?;
    final sdMinutes = sdText == null ? null : double.tryParse(sdText);
    if (sdText != null && (sdMinutes == null || sdMinutes <= 0)) {
      throw UsageException('--sd takes minutes: $sdText', usage);
    }
    final sdRate = CytonSampleRate.of(int.parse(args['sd-rate'] as String))!;
    if (sdRate != CytonSampleRate.hz250 && sdMinutes == null) {
      throw UsageException('--sd-rate is for --sd', usage);
    }
    final sd = sdMinutes == null
        ? null
        : CytonSdDuration.forMinutes(sdMinutes, sdRate);
    final markers = args['markers'] as bool;
    final board = await CytonBoard.connect(
      await serial.open(
        SerialPortInfo(id: rest.single),
        baudRate: cytonBaudRate,
      ),
      useDaisy: args['daisy'] as bool,
      sampleRate: sd == null ? CytonSampleRate.hz250 : sdRate,
      boardMode: markers ? CytonBoardMode.marker : CytonBoardMode.defaults,
    );
    final n = board.channelCount;
    final gain = int.parse(args['gain'] as String);
    final emg = _channels(args['emg'] as List<String>, n);
    final bipolar = {..._channels(args['bipolar'] as List<String>, n), ...emg};
    for (var ch = 1; ch <= n; ch++) {
      final s = CytonChannelSettings(gain: gain, srb2: !bipolar.contains(ch));
      if (s != const CytonChannelSettings()) {
        await board.configureChannel(ch, s);
      }
    }
    final name = args['name'] as String;
    final labels = [
      for (var c = 0; c < n; c++)
        args['ultracortex'] as bool ? _ultracortex[c] : 'ch${c + 1}',
    ];
    final eegChannels = [
      for (var c = 0; c < n; c++)
        if (!emg.contains(c + 1)) c,
    ];
    final emgChannels = [for (final c in emg.toList()..sort()) c - 1];
    final source = 'openbci-cyton:${rest.single}';
    final model = board.daisy ? 'Cyton + Daisy' : 'Cyton';

    Future<LslOutlet> outlet(
      String name,
      String type,
      List<int> channels,
      String suffix,
    ) => lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: type,
        channelCount: channels.length,
        rate: board.rate,
        sourceId: '$source$suffix',
        channels: [
          for (final c in channels) LSLChannel(labels[c], unit: 'microvolts'),
        ],
        desc: {
          'acquisition': {'manufacturer': 'OpenBCI', 'model': model},
        },
      ),
      const LslOutletOptions(),
    );

    // Above 250 Hz the board only records to the card.
    final publish = board.live;
    LslOutlet? eeg, emgOut, accel, markersOut;
    if (publish) {
      await lsl.prepare();
      if (eegChannels.isNotEmpty) {
        eeg = await outlet(name, 'EEG', eegChannels, '');
      }
      if (emgChannels.isNotEmpty) {
        emgOut = await outlet('$name EMG', 'EMG', emgChannels, ':emg');
      }
      if (markers) {
        markersOut = await lsl.createOutlet(
          LslOutletSpec(
            name: '$name markers',
            type: 'Markers',
            channelCount: 1,
            rate: 0,
            format: LSLChannelFormat.string,
            sourceId: '$source:markers',
          ),
          const LslOutletOptions(),
        );
      } else {
        accel = await lsl.createOutlet(
          LslOutletSpec(
            name: '$name accelerometer',
            type: 'Accelerometer',
            channelCount: 3,
            rate: board.rate,
            sourceId: '$source:accel',
            channels: const [
              LSLChannel('x', unit: 'g'),
              LSLChannel('y', unit: 'g'),
              LSLChannel('z', unit: 'g'),
            ],
          ),
          const LslOutletOptions(),
        );
      }
    }
    // Time stamps by the sample count, from the first sample's arrival.
    double? t0;
    var count = 0;
    final pending = <CytonSample>[];
    final sub = board.samples.listen((s) {
      t0 ??= lsl.clock();
      count += s.lost;
      pending.add(s);
    });
    var sent = 0, marked = 0, typedCount = 0;
    Float32List pick(List<int> channels, int m) {
      final k = channels.length;
      final v = Float32List(m * k);
      for (var i = 0; i < m; i++) {
        final eeg = pending[i].eeg;
        for (var j = 0; j < k; j++) {
          v[i * k + j] = eeg[channels[j]];
        }
      }
      return v;
    }

    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (pending.isEmpty || !publish) return;
      final m = pending.length;
      final times = Float64List(m);
      final a = Float32List(m * 3);
      for (var i = 0; i < m; i++) {
        final s = pending[i];
        times[i] = t0! + count++ / board.rate;
        a.setAll(i * 3, s.accel);
        final marker = s.marker;
        if (marker != null) {
          marked++;
          markersOut?.pushStrings([cytonMarkerLabel(marker)], [times[i]]);
        }
      }
      eeg?.push(pick(eegChannels, m), times);
      emgOut?.push(pick(emgChannels, m), times);
      accel?.push(a, times);
      pending.clear();
      sent += m;
    });

    if (sd != null) {
      out.writeln(await board.startSdRecording(sd));
    } else {
      await board.start();
    }
    out.writeln(
      [
        if (publish)
          'Publishing $name: ${eegChannels.length} EEG'
              '${emgChannels.isEmpty ? '' : ' and ${emgChannels.length} EMG'} '
              'channels at ${board.rate.toStringAsFixed(0)} Hz'
              '${board.daisy ? ' (with Daisy)' : ''}'
        else
          'Recording to the SD card at ${sdRate.hz} Hz (the board does not '
              'stream above 250 Hz)',
        if (sd != null) 'SD card file ${board.sdFile}',
        'Ctrl-C to stop',
      ].join('; '),
    );
    // Markers typed on standard input, once streaming.
    StreamSubscription<String>? typed;
    if (markers) {
      typed = stdin
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final text = line.trim();
            final value =
                int.tryParse(text) ??
                (text.length == 1 ? text.codeUnitAt(0) : null);
            if (value == null || !cytonMarkerIsSafe(value)) {
              out.writeln(
                'Not a marker: "$text" (128-239, or one of '
                '$cytonSafeMarkerChars)',
              );
            } else {
              typedCount++;
              board.marker(value);
            }
          });
    }

    await _untilStopped(stop);
    timer.cancel();
    await typed?.cancel();
    await sub.cancel();
    if (sd != null) out.writeln(await board.stopSdRecording());
    await board.close();
    for (final o in [eeg, emgOut, accel, markersOut]) {
      await o?.close();
    }
    if (publish) {
      out.writeln(
        'Sent $sent samples'
        '${markers ? ' and $marked of $typedCount markers' : ''}',
      );
    }
    return 0;
  }
}

class _CytonSd extends _Base {
  _CytonSd(super.out) {
    argParser
      ..addOption(
        'rate',
        allowed: [for (final r in CytonSampleRate.values) '${r.hz}'],
        help:
            'The sampling rate of the recording (default: estimated from the '
            'accelerometer, or 250).',
      )
      ..addOption(
        'gain',
        allowed: [for (final g in cytonGains) '$g'],
        defaultsTo: '24',
        help: 'The gain of all channels during the recording.',
      )
      ..addFlag(
        'ultracortex',
        defaultsTo: true,
        help: 'Name channels as the UltraCortex Mark IV electrodes.',
      )
      ..addMultiOption(
        'emg',
        help: 'Channels (1-16) that were used for EMG (their type).',
      );
  }

  @override
  String get name => 'cyton-sd';

  @override
  String get description =>
      'Convert a recording from the SD card of an OpenBCI Cyton '
      '(OBCI_XX.TXT) to XDF: the channels (µV), and the accelerometer (g) '
      'or the markers.';

  @override
  String get invocation => 'lsl cyton-sd <OBCI_XX.TXT> [<output.xdf>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty || rest.length > 2) {
      throw UsageException('One recording, and optionally the output', usage);
    }
    final input = File(rest.first);
    final output = File(
      rest.length > 1
          ? rest[1]
          : '${input.path.replaceFirst(RegExp(r'\.[^./\\]*$'), '')}.xdf',
    );
    final rate = args['rate'] as String?;
    final emg = _channels(args['emg'] as List<String>, 16);
    final sink = output.openWrite();
    final CytonSdSummary s;
    try {
      s = await convertCytonSdToXdf(
        input.openRead(),
        sink,
        name: input.uri.pathSegments.last,
        labels: args['ultracortex'] as bool ? _ultracortex : null,
        types: [for (var c = 1; c <= 16; c++) emg.contains(c) ? 'EMG' : 'EEG'],
        rate: rate == null ? null : double.parse(rate),
        gains: List.filled(16, int.parse(args['gain'] as String)),
      );
    } finally {
      await sink.close();
    }
    out.writeln(
      '${output.path}: ${s.channelCount} channels, ${s.samples} samples '
      '(${s.duration.toStringAsFixed(1)} s) at '
      '${s.layout.rate.toStringAsFixed(0)} Hz'
      '${s.layout.rateEstimated ? ' (estimated)' : ''}, '
      '${s.layout.hasAccel ? 'accelerometer' : '${s.markers} markers'}'
      '${s.lost > 0 ? ', ${s.lost} samples lost' : ''}',
    );
    return 0;
  }
}
