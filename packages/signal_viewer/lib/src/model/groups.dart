import 'package:flutter/foundation.dart';

import 'stream_info.dart';

/// The tab name, kind and channel names the user gave a stream (Source
/// setup), by its [StreamInfo.key]. They override what the source says
/// (a device's port configuration, an LSL stream's type and channel
/// labels) and apply to that stream of every device and recording.
class SourceAssignment {
  final String group;
  final Kind kind;

  /// Names of channels by index (0-based), e.g. the cap position `Cz`.
  final Map<int, String> names;

  const SourceAssignment(this.group, this.kind, {this.names = const {}});

  static SourceAssignment defaultFor(StreamInfo stream) =>
      SourceAssignment(stream.kind.label.toUpperCase(), stream.kind);

  SourceAssignment copyWith({
    String? group,
    Kind? kind,
    Map<int, String>? names,
  }) => SourceAssignment(
    group ?? this.group,
    kind ?? this.kind,
    names: names ?? this.names,
  );

  Map<String, Object?> toJson() => {
    'group': group,
    'kind': kind.name,
    if (names.isNotEmpty)
      'names': {for (final n in names.entries) '${n.key}': n.value},
  };

  static SourceAssignment fromJson(Map<Object?, Object?> json) =>
      SourceAssignment(
        json['group']! as String,
        Kind.values.byName(json['kind']! as String),
        names: {
          for (final n in ((json['names'] as Map?) ?? const {}).entries)
            int.parse(n.key as String): n.value as String,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is SourceAssignment &&
      other.group == group &&
      other.kind == kind &&
      mapEquals(other.names, names);

  @override
  int get hashCode => Object.hash(
    group,
    kind,
    Object.hashAllUnordered([
      for (final e in names.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// One displayed stream made of one or more streams of a source with the
/// same rate.
class StreamGroup {
  final StreamInfo info;
  final List<StreamInfo> members;

  const StreamGroup(this.info, this.members);

  bool get merged => members.length > 1;

  /// The member that channel [channel] of [info] comes from.
  StreamInfo memberOf(int channel) {
    final ref = info.channels[channel];
    return members.firstWhere((m) => m.channels.contains(ref));
  }
}

/// The index of a stream within its source (e.g. a device's port).
int streamIndex(StreamInfo stream) => stream.channels.first.stream;

/// "0–3, 5" for 0, 1, 2, 3, 5.
String indexList(List<int> indices) {
  final runs = <String>[];
  var start = indices.first, prev = indices.first;
  for (final p in [...indices.skip(1), null]) {
    if (p != null && p == prev + 1) {
      prev = p;
      continue;
    }
    runs.add(start == prev ? '$start' : '$start–$prev');
    if (p != null) start = prev = p;
  }
  return runs.join(', ');
}

/// [stream] with the kind and channel names of [a].
StreamInfo _assigned(StreamInfo stream, SourceAssignment a) {
  final n = a.names;
  return stream.copyWith(
    kind: a.kind,
    labels: [
      for (var c = 0; c < stream.labels.length; c++) n[c] ?? stream.labels[c],
    ],
    deviceLabels: stream.labels,
  );
}

StreamGroup _group(
  String name,
  Kind kind,
  List<StreamInfo> members,
  Map<String, SourceAssignment> assignments,
  String noun,
) {
  Map<int, String> names(StreamInfo s) => assignments[s.key]?.names ?? const {};
  if (members.length == 1) {
    final stream = members.first;
    final a = assignments[stream.key] ?? SourceAssignment.defaultFor(stream);
    return StreamGroup(
      _assigned(
        stream,
        a.copyWith(kind: kind),
      ).copyWith(name: '${stream.name} ($name)'),
      members,
    );
  }
  final device = [
    for (final m in members)
      for (final l in m.labels) '${m.tag}:$l',
  ];
  return StreamGroup(
    StreamInfo(
      key: 'group:$name:${members.first.rate}',
      name:
          '$name · $noun '
          '${indexList([for (final m in members) streamIndex(m)])}',
      kind: kind,
      rate: members.first.rate,
      labels: [
        for (var i = 0, k = 0; i < members.length; i++)
          for (var c = 0; c < members[i].labels.length; c++, k++)
            names(members[i])[c] ?? device[k],
      ],
      deviceLabels: device,
      units: [for (final m in members) ...m.units],
      channels: [for (final m in members) ...m.channels],
    ),
    members,
  );
}

/// The tabs for the [streams] of one source.
///
/// With [groupable] (streams on one clock, e.g. a device's ports), streams
/// with the same assigned tab name and sampling rate are merged, ordered by
/// their first stream; irregular and event streams are never merged
/// ([noun] names the members in merged tab names, e.g. `ports`).
/// Otherwise each stream is a tab of its own, with the assigned kind and
/// channel names.
List<StreamGroup> buildGroups(
  List<StreamInfo> streams,
  Map<String, SourceAssignment> assignments, {
  bool groupable = true,
  String noun = 'streams',
}) {
  if (!groupable) {
    return [
      for (final s in streams)
        StreamGroup(
          assignments[s.key] == null ? s : _assigned(s, assignments[s.key]!),
          [s],
        ),
    ];
  }
  final sorted = [...streams]..sort((a, b) => streamIndex(a) - streamIndex(b));
  final pools = <(String, double), (Kind, List<StreamInfo>)>{};
  final groups = <StreamGroup>[];
  for (final s in sorted) {
    final a = assignments[s.key] ?? SourceAssignment.defaultFor(s);
    if (s.irregular || a.kind == Kind.event) {
      groups.add(_group(a.group, a.kind, [s], assignments, noun));
      continue;
    }
    pools.putIfAbsent((a.group, s.rate), () => (a.kind, [])).$2.add(s);
  }
  for (final MapEntry(key: (name, _), value: (kind, members))
      in pools.entries) {
    groups.add(_group(name, kind, members, assignments, noun));
  }
  groups.sort(
    (a, b) => streamIndex(a.members.first) - streamIndex(b.members.first),
  );
  return groups;
}
