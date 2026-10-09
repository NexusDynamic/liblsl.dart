// Releases across the workspace: what is pending, version bumps that carry
// through to dependents, and the tags that start .github/workflows/release.yml.
//
//   dart run tool/release.dart [status] [--offline] [--check]
//   dart run tool/release.dart bump <package> <version|patch|minor|major> [--cascade]
//   dart run tool/release.dart tag [--push] [--no-test-check]
//   dart run tool/release.dart wait-deps <package> [--timeout <minutes>]
//
// See "Releases (maintainers)" in CONTRIBUTING.md.
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

final String root = File.fromUri(Platform.script).parent.parent.path;

const submodule = 'packages/liblsl/src/liblsl-dart_main';

/// Files that do not make a release necessary when they change.
final _notShipped = RegExp(
  r'(^|/)(test|benchmark|doc|paper|coverage)/|\.md$|\.iml$|'
  r'(^|/)(analysis_options|dart_test|pubspec_overrides)\.yaml$',
);

class Package {
  Package(this.name, this.dir, this.version, this.publishable, this.deps);

  final String name;

  /// Relative to the repository root: `packages/<name>` or `apps/<name>`.
  final String dir;
  Version version;
  final bool publishable;

  /// Workspace packages this one depends on, with the constraint as written,
  /// or null for a path dependency. Not `dev_dependencies`.
  final Map<String, String?> deps;

  Version? lastTag;

  /// Shipped files changed since [lastTag].
  int changed = 0;

  bool get isApp => dir.startsWith('apps/');

  /// A private package that is not an app is never released.
  bool get internal => !publishable && !isApp;

  /// The version without build metadata, as in the tag.
  Version get tagVersion => _withoutBuild(version);
  String get tag => '$name-v$tagVersion';

  bool get ready => !internal && (lastTag == null || tagVersion > lastTag!);
  bool get unbumped => !internal && !ready && changed > 0;
  String get state => internal
      ? 'internal'
      : ready
      ? 'ready'
      : unbumped
      ? 'unbumped'
      : 'released';

  File get pubspec => File('$root/$dir/pubspec.yaml');
  File get changelog => File('$root/$dir/CHANGELOG.md');
}

Version _withoutBuild(Version v) => Version(
  v.major,
  v.minor,
  v.patch,
  pre: v.preRelease.isEmpty ? null : v.preRelease.join('.'),
);

Never fail(String message, [int code = 1]) {
  stderr.writeln('error: $message');
  exit(code);
}

String run(String command, List<String> args, {bool check = true}) {
  final result = Process.runSync(command, args, workingDirectory: root);
  if (check && result.exitCode != 0) {
    fail('$command ${args.join(' ')}\n${result.stderr}'.trim());
  }
  return (result.stdout as String).trim();
}

List<String> lines(String text) =>
    text.split('\n').where((l) => l.trim().isNotEmpty).toList();

/// The releasable packages of the workspace, dependencies before dependents.
Map<String, Package> loadWorkspace() {
  final rootSpec = loadYaml(File('$root/pubspec.yaml').readAsStringSync());
  final packages = <String, Package>{};
  final specs = <String, YamlMap>{};
  for (final dir in (rootSpec['workspace'] as YamlList).cast<String>()) {
    final spec =
        loadYaml(File('$root/$dir/pubspec.yaml').readAsStringSync()) as YamlMap;
    final name = spec['name'] as String;
    // Only what release.yml can release: packages/<name> and apps/<name>.
    if (dir != 'packages/$name' && dir != 'apps/$name') continue;
    specs[name] = spec;
    packages[name] = Package(
      name,
      dir,
      Version.parse('${spec['version']}'),
      spec['publish_to'] != 'none',
      {},
    );
  }
  for (final package in packages.values) {
    final deps = specs[package.name]!['dependencies'];
    if (deps is! YamlMap) continue;
    for (final entry in deps.entries) {
      if (!packages.containsKey(entry.key)) continue;
      package.deps[entry.key as String] = entry.value is String
          ? entry.value as String
          : null;
    }
  }

  final tags = lines(run('git', ['tag', '--list', '*-v*']));
  for (final package in packages.values) {
    for (final tag in tags) {
      if (!tag.startsWith('${package.name}-v')) continue;
      final Version version;
      try {
        version = Version.parse(tag.substring(package.name.length + 2));
      } on FormatException {
        continue;
      }
      if (package.lastTag == null || version > package.lastTag!) {
        package.lastTag = version;
      }
    }
    if (package.lastTag == null) continue;
    package.changed = lines(
      run('git', [
        'diff',
        '--name-only',
        '${package.name}-v${package.lastTag}',
        '--',
        package.dir,
      ]),
    ).where((f) => !_notShipped.hasMatch(f)).length;
  }

  // Dependencies first.
  final sorted = <String, Package>{};
  void visit(Package package) {
    if (sorted.containsKey(package.name)) return;
    for (final dep in package.deps.keys) {
      visit(packages[dep]!);
    }
    sorted[package.name] = package;
  }

  packages.values.forEach(visit);
  return sorted;
}

bool hasChangelogHeading(Package package, Version version) =>
    package.changelog.existsSync() &&
    RegExp(
      '^#+\\s*\\[?v?${RegExp.escape('$version')}\\]?\\s*\$',
      multiLine: true,
    ).hasMatch(package.changelog.readAsStringSync());

/// The versions the liblsl citation files carry, by file name.
Map<String, String?> citationVersions() => {
  'CITATION.cff': RegExp(
    r'^version:\s*"?([^"\s]+)"?',
    multiLine: true,
  ).firstMatch(File('$root/CITATION.cff').readAsStringSync())?.group(1),
  for (final name in ['codemeta.json', '.zenodo.json'])
    name:
        (jsonDecode(File('$root/$name').readAsStringSync()) as Map)['version']
            as String?,
};

class Problems {
  final errors = <String>[];
  final warnings = <String>[];
  final notes = <String>[];
}

/// What is wrong with the workspace as it stands. With [checkOnly], only what
/// is wrong at any time, whether or not a release is being prepared.
Problems findProblems(Map<String, Package> packages, {bool checkOnly = false}) {
  final problems = Problems();
  for (final package in packages.values) {
    for (final MapEntry(key: depName, value: constraint)
        in package.deps.entries) {
      final dep = packages[depName]!;
      if (constraint == null) {
        if (package.publishable) {
          problems.errors.add(
            '${package.name} depends on $depName by path, which pub.dev '
            'does not accept',
          );
        }
        continue;
      }
      final range = VersionConstraint.parse(constraint);
      if (!range.allows(dep.version)) {
        problems.errors.add(
          '${package.name} wants $depName $constraint, but the workspace '
          'has ${dep.version}',
        );
      } else if (dep.ready &&
          range is VersionRange &&
          range.min != null &&
          range.min! < dep.tagVersion) {
        problems.notes.add(
          '${package.name} allows $depName $constraint; to require '
          '${dep.tagVersion}: bump $depName ${dep.tagVersion} --cascade',
        );
      }
      if (!checkOnly && package.ready && dep.unbumped) {
        problems.errors.add(
          '${package.name} is ready, but $depName has changed since '
          '${dep.name}-v${dep.lastTag} without a new version',
        );
      }
    }
    if (checkOnly) continue;
    if (package.unbumped) {
      problems.warnings.add(
        '${package.name}: ${package.changed} shipped file(s) changed since '
        '${package.name}-v${package.lastTag}, version unchanged',
      );
    }
    if (package.ready && !hasChangelogHeading(package, package.tagVersion)) {
      problems.errors.add(
        '${package.name}: no ${package.tagVersion} heading in '
        '${package.dir}/CHANGELOG.md',
      );
    }
  }
  if (checkOnly) return problems;

  final liblsl = packages['liblsl'];
  if (liblsl != null) {
    for (final MapEntry(key: file, value: version)
        in citationVersions().entries) {
      if (version != '${liblsl.tagVersion}') {
        problems.errors.add(
          '$file has version $version, liblsl is ${liblsl.tagVersion} '
          '(bump liblsl ${liblsl.tagVersion} sets it)',
        );
      }
    }
  }
  if (File('$root/$submodule/.git').existsSync() ||
      Directory('$root/$submodule/.git').existsSync()) {
    if (run('git', ['-C', submodule, 'status', '--porcelain']).isNotEmpty) {
      problems.errors.add('the liblsl submodule has uncommitted changes');
    }
    if (run('git', [
      '-C',
      submodule,
      'branch',
      '-r',
      '--contains',
      'HEAD',
    ]).isEmpty) {
      problems.errors.add(
        'the liblsl submodule is at a commit that is on no remote branch: '
        'push it, or CI cannot check it out',
      );
    }
    if (run('git', ['diff', '--name-only', '--', submodule]).isNotEmpty) {
      problems.errors.add(
        'the liblsl submodule is at a commit other than the one recorded',
      );
    }
  }
  return problems;
}

Future<bool?> onPubDev(String name, Version version) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(
      Uri.parse('https://pub.dev/api/packages/$name/versions/$version'),
    );
    final response = await request.close();
    await response.drain<void>();
    return switch (response.statusCode) {
      200 => true,
      404 => false,
      _ => null,
    };
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<Problems> status(
  Map<String, Package> packages, {
  bool offline = false,
}) async {
  final published = <String, bool?>{};
  if (!offline) {
    await Future.wait([
      for (final p in packages.values.where((p) => p.publishable))
        onPubDev(p.name, p.tagVersion).then((v) => published[p.name] = v),
    ]);
  }
  final rows = [
    ['package', 'version', 'last tag', 'pub.dev', 'changed', 'state'],
    for (final p in packages.values)
      [
        p.name,
        '${p.version}',
        '${p.lastTag ?? '-'}',
        !p.publishable
            ? '-'
            : switch (published[p.name]) {
                true => 'yes',
                false => 'no',
                null => '?',
              },
        p.lastTag == null ? '-' : '${p.changed}',
        p.state,
      ],
  ];
  final widths = [
    for (var c = 0; c < rows.first.length; c++)
      rows.map((r) => r[c].length).reduce((a, b) => a > b ? a : b),
  ];
  for (final row in rows) {
    print(
      [
        for (var c = 0; c < row.length; c++) row[c].padRight(widths[c]),
      ].join('  ').trimRight(),
    );
  }
  final problems = findProblems(packages);
  void section(String title, List<String> items) {
    if (items.isEmpty) return;
    print('\n$title');
    for (final item in items) {
      print('  $item');
    }
  }

  section('Errors', problems.errors);
  section('Warnings', problems.warnings);
  section('Notes', problems.notes);
  final ready = packages.values.where((p) => p.ready).map((p) => p.tag);
  print('\nTo release: ${ready.isEmpty ? 'nothing' : ready.join(' ')}');
  return problems;
}

void replaceIn(File file, RegExp pattern, String Function(Match) replace) {
  final text = file.readAsStringSync();
  if (!pattern.hasMatch(text)) {
    fail('${file.path}: nothing matches ${pattern.pattern}');
  }
  file.writeAsStringSync(text.replaceAllMapped(pattern, replace));
}

/// Sets [package]'s version, and with it the citation files (liblsl) or the
/// download links in the READMEs (apps). An app keeps its build number unless
/// [version] has one.
void setVersion(Package package, Version version) {
  if (version.build.isEmpty && package.version.build.isNotEmpty) {
    version = Version.parse('$version+${package.version.build.join('.')}');
  }
  replaceIn(
    package.pubspec,
    RegExp(r'^version:.*$', multiLine: true),
    (_) => 'version: $version',
  );
  package.version = version;
  final tagVersion = package.tagVersion;
  print('${package.name} $version');

  // `[<text> <version>](…/releases/tag/<app>-v<version>)`. Prereleases are
  // not linked.
  if (package.isApp && !tagVersion.isPreRelease) {
    final link = RegExp(
      '\\[([^\\]0-9]*)[^\\]]*\\]\\((https://github.com/[^/]+/[^/]+/releases/tag/'
      '${package.name}-v)[^)]*\\)',
    );
    for (final readme in [
      File('$root/README.md'),
      File('$root/${package.dir}/README.md'),
    ]) {
      if (!readme.existsSync()) continue;
      final text = readme.readAsStringSync();
      readme.writeAsStringSync(
        text.replaceAllMapped(
          link,
          (m) => '[${m[1]}$tagVersion](${m[2]}$tagVersion)',
        ),
      );
    }
  }

  if (package.name == 'liblsl') {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final cff = File('$root/CITATION.cff');
    replaceIn(
      cff,
      RegExp(r'^version:.*$', multiLine: true),
      (_) => 'version: "$tagVersion"',
    );
    replaceIn(
      cff,
      RegExp(r'^date-released:.*$', multiLine: true),
      (_) => 'date-released: "$today"',
    );
    // Top-level keys only (two spaces in), edited in place so the rest of
    // the file is left as it is.
    void setKey(String file, String key, String value) => replaceIn(
      File('$root/$file'),
      RegExp('^  "$key": "[^"]*"', multiLine: true),
      (_) => '  "$key": "$value"',
    );
    setKey('codemeta.json', 'version', '$tagVersion');
    setKey('codemeta.json', 'dateModified', today);
    setKey(
      'codemeta.json',
      'downloadUrl',
      'https://pub.dev/api/archives/liblsl-$tagVersion.tar.gz',
    );
    setKey('.zenodo.json', 'version', '$tagVersion');
  }
}

/// Makes sure [package]'s CHANGELOG has a section for its version, and that
/// [line], if given, is in it.
void noteInChangelog(Package package, [String? line]) {
  final file = package.changelog;
  var text = file.existsSync() ? file.readAsStringSync() : '';
  final version = package.tagVersion;
  if (!hasChangelogHeading(package, version)) {
    final first = RegExp(r'^(#+)\s*(.*)$', multiLine: true).firstMatch(text);
    final hashes = first?.group(1) ?? '##';
    if (first != null && first.group(2)!.toLowerCase() == 'unreleased') {
      // What was unreleased is this version.
      text = text.replaceRange(first.start, first.end, '$hashes $version');
    } else {
      text = '$hashes $version\n\n$text';
    }
  }
  if (line != null) {
    final heading = RegExp(
      '^(#+)\\s*\\[?v?${RegExp.escape('$version')}\\]?\\s*\$',
      multiLine: true,
    ).firstMatch(text)!;
    final next = RegExp(
      '^#{1,${heading.group(1)!.length}}\\s',
      multiLine: true,
    ).firstMatch(text.substring(heading.end));
    final end = next == null ? text.length : heading.end + next.start;
    final section = text.substring(heading.end, end);
    if (!section.contains(line)) {
      text =
          '${text.substring(0, heading.end)}'
          '${section.trimRight()}\n$line\n${next == null ? '' : '\n'}'
          '${text.substring(end)}';
    }
  }
  file.writeAsStringSync(text);
}

Future<void> bump(Map<String, Package> packages, List<String> args) async {
  final cascade = args.remove('--cascade');
  if (args.length != 2) {
    fail('usage: bump <package> <version|patch|minor|major> [--cascade]', 64);
  }
  final target =
      packages[args[0]] ?? fail('no package or app named ${args[0]}', 66);
  if (target.internal) fail('${target.name} is private and is not released');
  final Version version;
  try {
    version = switch (args[1]) {
      'patch' => target.tagVersion.nextPatch,
      'minor' => target.tagVersion.nextMinor,
      'major' => target.tagVersion.nextMajor,
      _ => Version.parse(args[1]),
    };
  } on FormatException {
    fail("'${args[1]}' is not a semantic version", 65);
  }
  setVersion(target, version);
  noteInChangelog(target);

  if (cascade) {
    // Every package that has the target below it, dependencies first, so a
    // dependent sees the new versions of everything it depends on.
    final moved = {target.name};
    for (final package in packages.values) {
      final from = package.deps.keys.where(moved.contains).toList();
      if (from.isEmpty) continue;
      moved.add(package.name);
      if (package.internal) continue;
      if (!package.ready) setVersion(package, package.tagVersion.nextPatch);
      noteInChangelog(package);
      for (final depName in from) {
        final constraint = package.deps[depName];
        if (constraint == null) continue;
        final dep = packages[depName]!;
        final range = VersionConstraint.parse(constraint);
        if (range is VersionRange &&
            range.min != null &&
            range.min! >= dep.tagVersion) {
          continue;
        }
        final raised = '^${dep.tagVersion}';
        replaceIn(
          package.pubspec,
          RegExp(
            '^(  $depName:[ \\t]*)${RegExp.escape(constraint)}',
            multiLine: true,
          ),
          (m) => '${m[1]}$raised',
        );
        package.deps[depName] = raised;
        noteInChangelog(package, '- Requires `$depName` $raised.');
        print('  ${package.name}: $depName $constraint -> $raised');
      }
    }
  }

  stdout.writeln('\nResolving the workspace...');
  final get = Process.runSync('dart', ['pub', 'get'], workingDirectory: root);
  if (get.exitCode != 0) fail('dart pub get failed:\n${get.stderr}');
  print('');
  await status(loadWorkspace());
  print('\nNext: review the diff and the CHANGELOG sections, commit, push,');
  print('wait for Test to pass, then `dart run tool/release.dart tag`.');
}

Future<void> tag(Map<String, Package> packages, List<String> args) async {
  final push = args.remove('--push');
  final testCheck = !args.remove('--no-test-check');
  if (args.isNotEmpty) fail('usage: tag [--push] [--no-test-check]', 64);

  run('git', ['fetch', '--quiet', '--tags', 'origin', 'main']);
  packages = loadWorkspace();
  final problems = findProblems(packages);
  final blockers = [
    ...problems.errors,
    if (run('git', ['status', '--porcelain']).isNotEmpty)
      'the working tree has uncommitted changes',
    if (run('git', ['branch', '--show-current']) != 'main')
      'not on the main branch',
    if (run('git', ['rev-parse', 'HEAD']) !=
        run('git', ['rev-parse', 'origin/main']))
      'HEAD is not origin/main: push (or pull) first',
  ];
  final ready = packages.values.where((p) => p.ready).toList();
  if (ready.isEmpty) {
    print('Nothing to release.');
    return;
  }
  if (testCheck && blockers.isEmpty) {
    // As release.yml looks: a release run repeats the whole suite if Test
    // has not passed on the commit, once for every tag.
    final sha = run('git', ['rev-parse', 'HEAD']);
    final passed = Process.runSync('gh', [
      'api',
      'repos/{owner}/{repo}/actions/workflows/test.yml/runs?head_sha=$sha',
      '--jq',
      'any(.workflow_runs[]; .conclusion == "success")',
    ], workingDirectory: root);
    if (passed.exitCode != 0) {
      blockers.add(
        'could not ask GitHub whether Test passed (gh: '
        '${'${passed.stderr}'.trim()}); --no-test-check skips this',
      );
    } else if ('${passed.stdout}'.trim() != 'true') {
      blockers.add(
        'Test has not passed on ${sha.substring(0, 7)} yet; wait for it, '
        'or use --no-test-check and let every release run the suite',
      );
    }
  }
  print('${push ? 'Releasing' : 'Would release'}, in this order:');
  for (final package in ready) {
    print('  ${package.tag}');
  }
  if (blockers.isNotEmpty) {
    print('\nNot yet:');
    for (final blocker in blockers) {
      print('  $blocker');
    }
    exit(1);
  }
  if (!push) {
    print('\nNothing was tagged. Add --push to tag and push these.');
    return;
  }
  for (final package in ready) {
    run('git', ['tag', package.tag]);
    // One push per tag: GitHub starts no workflow at all for a push that
    // carries more than three tags.
    run('git', ['push', '--quiet', 'origin', package.tag]);
    print('pushed ${package.tag}');
  }
}

/// Waits until the workspace dependencies of a package that are being
/// released with it are on pub.dev. A dependency is being released if its
/// current version has a tag on the remote.
Future<void> waitDeps(Map<String, Package> packages, List<String> args) async {
  var minutes = 60;
  final at = args.indexOf('--timeout');
  if (at >= 0 && at + 1 < args.length) {
    minutes = int.parse(args[at + 1]);
    args.removeRange(at, at + 2);
  }
  if (args.length != 1) {
    fail('usage: wait-deps <package> [--timeout <minutes>]', 64);
  }
  final package =
      packages[args[0]] ?? fail('no package or app named ${args[0]}', 66);
  final deadline = DateTime.now().add(Duration(minutes: minutes));
  for (final depName in package.deps.keys) {
    final dep = packages[depName]!;
    if (!dep.publishable) continue;
    final tagged = run('git', [
      'ls-remote',
      '--tags',
      'origin',
      'refs/tags/${dep.tag}',
    ]).isNotEmpty;
    if (!tagged) {
      print('$depName ${dep.tagVersion}: no ${dep.tag} tag, not waiting');
      continue;
    }
    while (true) {
      if (await onPubDev(dep.name, dep.tagVersion) == true) {
        print('$depName ${dep.tagVersion}: on pub.dev');
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(
          '$depName ${dep.tagVersion} is not on pub.dev after $minutes '
          'minutes; ${package.name} needs it. Check the ${dep.tag} release '
          'run, then run this one again.',
        );
      }
      print('$depName ${dep.tagVersion}: not on pub.dev yet, waiting');
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  }
}

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final command = args.isEmpty || args.first.startsWith('-')
      ? 'status'
      : args.removeAt(0);
  final packages = loadWorkspace();
  switch (command) {
    case 'status':
      if (args.remove('--check')) {
        final problems = findProblems(packages, checkOnly: true);
        problems.errors.forEach(stderr.writeln);
        if (problems.errors.isNotEmpty) exit(1);
        print('Workspace dependencies are consistent.');
        return;
      }
      final problems = await status(
        packages,
        offline: args.remove('--offline'),
      );
      if (problems.errors.isNotEmpty) exit(1);
    case 'bump':
      await bump(packages, args);
    case 'tag':
      await tag(packages, args);
    case 'wait-deps':
      await waitDeps(packages, args);
    default:
      fail('unknown command $command (status, bump, tag, wait-deps)', 64);
  }
}
