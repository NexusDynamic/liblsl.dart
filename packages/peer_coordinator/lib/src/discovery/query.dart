import 'package:peer_coordinator/framework.dart';

/// A field of a [PeerDescriptor] that a [DiscoveryQuery] can filter on.
enum PeerField {
  /// [PeerDescriptor.streamName] — String.
  streamName,

  /// [PeerDescriptor.sessionName] — String.
  sessionName,

  /// [PeerDescriptor.nodeId] — String.
  nodeId,

  /// [PeerDescriptor.nodeUId] — String.
  nodeUId,

  /// [PeerDescriptor.nodeRole] — String.
  nodeRole,

  /// [PeerDescriptor.capabilities] — a set; [MatchOp.contains] tests
  /// membership, [MatchOp.equals] compares the comma-joined form.
  capabilities,

  /// [PeerDescriptor.randomRoll] — numeric. Compared numerically.
  randomRoll,

  /// [PeerDescriptor.startedAt] — ISO-8601, where lexicographic order is
  /// chronological order.
  startedAt,
}

/// How a [FieldMatch] compares a field to its value.
enum MatchOp { equals, startsWith, endsWith, contains, lessThan, greaterThan }

/// A transport-neutral peer filter.
///
/// This replaces the raw XPath predicate strings the LSL transport used to
/// build by concatenation. Transports that can resolve peers locally (the
/// in-memory bus, the WebSocket hub) evaluate the tree directly with [matches];
/// the LSL transport compiles it to XPath, because that is the only query
/// language its resolver speaks.
///
/// Keeping this a data structure rather than a string is what makes discovery
/// portable — and it removes a whole class of quoting bugs, since values never
/// have to survive being spliced into a query language.
sealed class DiscoveryQuery {
  const DiscoveryQuery();

  /// Whether [peer] satisfies this query.
  bool matches(PeerDescriptor peer);

  Map<String, dynamic> toJson();

  static DiscoveryQuery fromJson(Map<String, dynamic> json) {
    switch (json['op'] as String) {
      case 'and':
        return AndQuery(_terms(json));
      case 'or':
        return OrQuery(_terms(json));
      case 'not':
        return NotQuery(
          DiscoveryQuery.fromJson(json['term'] as Map<String, dynamic>),
        );
      case 'always':
        return const AlwaysMatch();
      case 'field':
        return FieldMatch(
          PeerField.values.byName(json['field'] as String),
          MatchOp.values.byName(json['match'] as String),
          json['value'] as Object,
        );
      default:
        throw FormatException('Unknown DiscoveryQuery op: ${json['op']}');
    }
  }

  static List<DiscoveryQuery> _terms(Map<String, dynamic> json) =>
      (json['terms'] as List)
          .map((t) => DiscoveryQuery.fromJson(t as Map<String, dynamic>))
          .toList();

  /// All of [terms] must match. An empty list matches everything.
  factory DiscoveryQuery.all(List<DiscoveryQuery> terms) = AndQuery;

  /// Any of [terms] must match. An empty list matches nothing.
  factory DiscoveryQuery.any(List<DiscoveryQuery> terms) = OrQuery;

  /// Negates [term].
  factory DiscoveryQuery.not(DiscoveryQuery term) = NotQuery;
}

/// Compares one [PeerField] against [value].
final class FieldMatch extends DiscoveryQuery {
  const FieldMatch(this.field, this.op, this.value);

  /// Shorthand for the overwhelmingly common case.
  const FieldMatch.equals(this.field, this.value) : op = MatchOp.equals;

  final PeerField field;
  final MatchOp op;

  /// A [String] for every field except [PeerField.randomRoll], which takes a
  /// [double].
  final Object value;

  @override
  bool matches(PeerDescriptor peer) {
    switch (field) {
      case PeerField.randomRoll:
        final actual = peer.randomRoll;
        if (actual == null) return false;
        final expected = (value as num).toDouble();
        return switch (op) {
          MatchOp.lessThan => actual < expected,
          MatchOp.greaterThan => actual > expected,
          MatchOp.equals => actual == expected,
          _ => throw StateError('$op is not valid for a numeric field'),
        };
      case PeerField.capabilities:
        final caps = peer.capabilities;
        return switch (op) {
          // Membership — 'does the node declare this capability'.
          MatchOp.contains => caps.contains(value as String),
          // Equality against the comma-joined form, matching how the LSL
          // transport publishes the field.
          MatchOp.equals => caps.join(',') == value as String,
          _ => throw StateError('$op is not valid for capabilities'),
        };
      case PeerField.streamName:
      case PeerField.sessionName:
      case PeerField.nodeId:
      case PeerField.nodeUId:
      case PeerField.nodeRole:
      case PeerField.startedAt:
        final actual = _stringField(peer);
        if (actual == null) return false;
        final expected = value as String;
        return switch (op) {
          MatchOp.equals => actual == expected,
          MatchOp.startsWith => actual.startsWith(expected),
          MatchOp.endsWith => actual.endsWith(expected),
          MatchOp.contains => actual.contains(expected),
          // Lexicographic, which is what makes ISO-8601 ordering work.
          MatchOp.lessThan => actual.compareTo(expected) < 0,
          MatchOp.greaterThan => actual.compareTo(expected) > 0,
        };
    }
  }

  String? _stringField(PeerDescriptor peer) => switch (field) {
    PeerField.streamName => peer.streamName,
    PeerField.sessionName => peer.sessionName,
    PeerField.nodeId => peer.nodeId,
    PeerField.nodeUId => peer.nodeUId,
    PeerField.nodeRole => peer.nodeRole,
    PeerField.startedAt => peer.startedAt,
    _ => throw StateError('$field is not a string field'),
  };

  @override
  Map<String, dynamic> toJson() => {
    'op': 'field',
    'field': field.name,
    'match': op.name,
    'value': value,
  };

  @override
  String toString() => '${field.name} ${op.name} $value';
}

/// Conjunction. An empty [terms] matches everything.
final class AndQuery extends DiscoveryQuery {
  const AndQuery(this.terms);
  final List<DiscoveryQuery> terms;

  @override
  bool matches(PeerDescriptor peer) => terms.every((t) => t.matches(peer));

  @override
  Map<String, dynamic> toJson() => {
    'op': 'and',
    'terms': terms.map((t) => t.toJson()).toList(),
  };

  @override
  String toString() => '(${terms.join(' and ')})';
}

/// Disjunction. An empty [terms] matches nothing.
final class OrQuery extends DiscoveryQuery {
  const OrQuery(this.terms);
  final List<DiscoveryQuery> terms;

  @override
  bool matches(PeerDescriptor peer) => terms.any((t) => t.matches(peer));

  @override
  Map<String, dynamic> toJson() => {
    'op': 'or',
    'terms': terms.map((t) => t.toJson()).toList(),
  };

  @override
  String toString() => '(${terms.join(' or ')})';
}

/// Negation.
final class NotQuery extends DiscoveryQuery {
  const NotQuery(this.term);
  final DiscoveryQuery term;

  @override
  bool matches(PeerDescriptor peer) => !term.matches(peer);

  @override
  Map<String, dynamic> toJson() => {'op': 'not', 'term': term.toJson()};

  @override
  String toString() => 'not($term)';
}

/// Matches every peer.
///
/// Transports whose query language cannot express "everything" (LSL requires
/// at least one condition) must reject this explicitly rather than silently
/// narrowing it.
final class AlwaysMatch extends DiscoveryQuery {
  const AlwaysMatch();

  @override
  bool matches(PeerDescriptor peer) => true;

  @override
  Map<String, dynamic> toJson() => const {'op': 'always'};

  @override
  String toString() => '*';
}
