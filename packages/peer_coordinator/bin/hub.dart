/// Standalone WebSocket relay hub.
///
///     dart run peer_coordinator:hub --session MyGame --secret-file ./secret
///
/// Nodes coordinate through it with a `WebSocketTransportConfig` carrying the
/// same session name and secret.
///
/// The hub is role-blind: it relays frames and tracks who is connected, and
/// knows nothing about election, membership or streams. What it does enforce is
/// entry — every connection proves knowledge of the shared secret before the
/// hub honours a single frame — and the identity each peer then publishes
/// under.
///
/// **This is research software.** Everyone holding the secret is fully trusted:
/// they can see every peer and subscribe to every stream. Put it behind a
/// reverse proxy rather than on a public interface; `deploy/` has a compose
/// stack that does exactly that.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:peer_coordinator/hub.dart';
import 'package:peer_coordinator/peer_coordinator.dart';

const _usage = '''
Usage: dart run peer_coordinator:hub [options]

  --session <name>       Session this hub hosts. Required.
  --secret <value>       Shared secret. Prefer --secret-file or HUB_SECRET;
                         a value here is visible in the process list.
  --secret-file <path>   Read the secret from a file (first line, trimmed).
  --host <address>       Bind address. Default 127.0.0.1. A non-loopback bind
                         is refused unless the session has a secret.
  --port <n>             Bind port. Default 8080.
  --session-ttl <sec>    End the session automatically after this long.
  --max-frame-bytes <n>  Largest accepted frame. Default 1048576.
  --max-connections <n>  Concurrent sockets. Default 64.
  --max-peers <n>        Registered endpoints. Default 256.
  --admin-port <n>       Enable the loopback admin API on this port.
  --admin-token <value>  Bearer token for the admin API. Required with it.
  --generate-secret      Print a fresh secret and exit.
  -h, --help             Show this.

Environment: HUB_SECRET, HUB_ADMIN_TOKEN (both override nothing; used when the
corresponding flag is absent).

Once running, stdin accepts: status, end, open <secret>, revoke <nodeUId>.
''';

Future<void> main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(Log.defaultPrinter);

  final Map<String, String> options;
  try {
    options = _parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n');
    stderr.writeln(_usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }
  if (options.containsKey('generate-secret')) {
    stdout.writeln(HubCredentials.generateSecret());
    return;
  }

  final session = options['session'];
  if (session == null || session.isEmpty) {
    stderr.writeln('Missing --session.\n');
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final secret = _resolveSecret(options);
  if (secret == null) {
    stderr.writeln(
      'Missing secret. Pass --secret-file, set HUB_SECRET, or run with\n'
      '--generate-secret to mint one. A hub without a secret would accept\n'
      'anyone who can reach the port, so there is no unauthenticated mode.\n',
    );
    exitCode = 64;
    return;
  }

  final host = options['host'] ?? '127.0.0.1';
  final InternetAddress address;
  try {
    address = InternetAddress(host);
  } on ArgumentError {
    stderr.writeln('--host must be an IP address, not a hostname: $host');
    exitCode = 64;
    return;
  }

  final adminPort = _intOption(options, 'admin-port');
  final adminToken =
      options['admin-token'] ?? Platform.environment['HUB_ADMIN_TOKEN'];
  if (adminPort != null && (adminToken == null || adminToken.isEmpty)) {
    stderr.writeln(
      '--admin-port needs --admin-token (or HUB_ADMIN_TOKEN). An unguarded\n'
      'control API can end your session or readmit anyone.',
    );
    exitCode = 64;
    return;
  }

  final ttlSeconds = _intOption(options, 'session-ttl');
  final limits = WsLimits(
    maxFrameBytes:
        _intOption(options, 'max-frame-bytes') ?? WsLimits.defaultMaxFrameBytes,
    maxConnections: _intOption(options, 'max-connections') ?? 64,
    maxPeers: _intOption(options, 'max-peers') ?? 256,
  );

  final hub = await CoordinationHub.serve(
    credentials: HubCredentials(session: session, secret: secret),
    address: address,
    port: _intOption(options, 'port') ?? 8080,
    limits: limits,
    sessionTtl: ttlSeconds == null ? null : Duration(seconds: ttlSeconds),
  );

  HubAdminServer? admin;
  if (adminPort != null) {
    admin = await HubAdminServer.serve(
      hub: hub,
      token: adminToken!,
      port: adminPort,
    );
  }

  stdout
    ..writeln('Coordination hub on ws://${address.address}:${hub.port}')
    ..writeln('  session "$session", epoch ${hub.epoch}')
    ..writeln(
      '  max frame ${limits.maxFrameBytes} bytes, '
      'max ${limits.maxConnections} connections',
    )
    ..writeln(
      ttlSeconds == null
          ? '  no time limit'
          : '  ends automatically in ${ttlSeconds}s',
    );
  if (admin != null) {
    stdout.writeln('  admin API on http://127.0.0.1:${admin.port}');
  }
  if (!address.isLoopback) {
    stdout.writeln(
      '  NOTE: bound to a non-loopback address. This hub speaks ws://, not\n'
      '  wss://, and every peer holding the secret is fully trusted. Prefer\n'
      '  loopback behind the reverse proxy in deploy/.',
    );
  }
  stdout.writeln(
    'Commands: status, end, open <secret>, revoke <uid>. '
    'Ctrl-C to stop.',
  );

  final commands = _readCommands(hub);
  await ProcessSignal.sigint.watch().first;
  await commands.cancel();
  await admin?.close();
  await hub.close();
}

/// Session control from the terminal, for an interactively run hub.
///
/// The admin API is the answer under docker or systemd; this is the answer when
/// you are sitting in front of it.
StreamSubscription<String> _readCommands(CoordinationHub hub) => systemEncoding
    .decoder
    .bind(stdin)
    .transform(const LineSplitter())
    .listen((line) async {
      final parts = line.trim().split(RegExp(r'\s+'));
      switch (parts.first) {
        case '':
          break;
        case 'status':
          stdout.writeln(
            'session "${hub.sessionName}" epoch ${hub.epoch} '
            '${hub.status.name}: ${hub.connectionCount} connections, '
            '${hub.endpointCount} endpoints',
          );
        case 'end':
          await hub.endSession();
          stdout.writeln('Session ended. Everyone disconnected.');
        case 'open':
          if (parts.length < 2 || parts[1].isEmpty) {
            stdout.writeln(
              'open needs a secret: open <secret>. Reopening means choosing '
              'the credential for the next cohort — reuse the old one only if '
              'you mean to readmit the previous participants.',
            );
            break;
          }
          hub.openSession(secret: parts[1]);
          stdout.writeln('Session open at epoch ${hub.epoch}.');
        case 'revoke':
          if (parts.length < 2) {
            stdout.writeln('revoke needs a nodeUId: revoke <uid>');
            break;
          }
          await hub.revoke(parts[1]);
          stdout.writeln('${parts[1]} revoked and disconnected.');
        default:
          stdout.writeln('Unknown command. Try: status, end, open, revoke.');
      }
    });

String? _resolveSecret(Map<String, String> options) {
  final path = options['secret-file'];
  if (path != null) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('--secret-file does not exist: $path');
      return null;
    }
    final lines = file.readAsLinesSync();
    final secret = lines.isEmpty ? '' : lines.first.trim();
    return secret.isEmpty ? null : secret;
  }
  final inline = options['secret'];
  if (inline != null && inline.isNotEmpty) return inline;
  final env = Platform.environment['HUB_SECRET'];
  return env == null || env.isEmpty ? null : env;
}

int? _intOption(Map<String, String> options, String name) {
  final raw = options[name];
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) throw FormatException('--$name must be a number: $raw');
  return value;
}

/// A small flag parser.
///
/// Replaces a hand-rolled loop that silently ignored a flag in the last
/// position — so `--host 0.0.0.0` at the end of the line bound to loopback
/// while looking like it had not.
Map<String, String> _parse(List<String> args) {
  const flags = {'help', 'generate-secret'};
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h') {
      options['help'] = '';
      continue;
    }
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    final name = arg.substring(2);
    if (flags.contains(name)) {
      options[name] = '';
      continue;
    }
    if (i + 1 >= args.length) {
      throw FormatException('--$name needs a value');
    }
    options[name] = args[++i];
  }
  return options;
}
