import 'package:liblsl_coordinator/framework.dart';
import 'package:liblsl_coordinator/transports/lsl.dart';

/// Compiles a [DiscoveryQuery] into an LSL XPath predicate.
///
/// LSL's resolver only speaks XPath, so the LSL transport is the one place
/// where a query has to become a string. Every other transport evaluates
/// [DiscoveryQuery.matches] directly.
///
/// Output is byte-identical to what `LSLStreamInfoHelper.generatePredicate`
/// used to emit for the same filter, which the golden tests in
/// `test/characterisation/predicate_golden_test.dart` enforce.
abstract final class LslPredicateCompiler {
  /// XPath location for each queryable field.
  ///
  /// [PeerField.streamName] is the bare `name` attribute; everything else
  /// lives in the stream's `desc` metadata, published by
  /// `LSLStreamInfoHelper.generateStreamInfo`.
  static String _path(PeerField field) => switch (field) {
    PeerField.streamName => 'name',
    PeerField.sessionName =>
      '//info/desc/${LSLStreamInfoHelper.sessionNameKey}',
    PeerField.nodeId => '//info/desc/${LSLStreamInfoHelper.nodeIdKey}',
    PeerField.nodeUId => '//info/desc/${LSLStreamInfoHelper.nodeUIdKey}',
    PeerField.nodeRole => '//info/desc/${LSLStreamInfoHelper.nodeRoleKey}',
    PeerField.capabilities =>
      '//info/desc/${LSLStreamInfoHelper.nodeCapabilitiesKey}',
    PeerField.randomRoll => '//info/desc/${LSLStreamInfoHelper.randomRollKey}',
    PeerField.startedAt =>
      '//info/desc/${LSLStreamInfoHelper.nodeStartedAtKey}',
  };

  /// Renders [value] as an XPath string literal.
  ///
  /// XPath 1.0 has no escape syntax inside literals, so a value containing
  /// both quote characters can only be expressed with `concat()`. The previous
  /// implementation interpolated values directly, so a single apostrophe in a
  /// session name or node id produced a malformed predicate — which LSL
  /// reports as a resolve that silently matches nothing.
  static String xpathLiteral(String value) {
    if (!value.contains("'")) return "'$value'";
    if (!value.contains('"')) return '"$value"';
    // Contains both: split on ' and rejoin with an escaped apostrophe.
    final parts = value.split("'");
    final pieces = <String>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) pieces.add("'${parts[i]}'");
      if (i < parts.length - 1) pieces.add('"\'"');
    }
    return 'concat(${pieces.join(', ')})';
  }

  /// Compiles [query] to an XPath predicate.
  ///
  /// Throws [ArgumentError] for a query that matches everything: LSL requires
  /// at least one condition, and silently substituting a match-all would turn
  /// a scoped resolve into a machine-wide one.
  static String compile(DiscoveryQuery query) {
    final compiled = _compile(query, topLevel: true);
    if (compiled == null) {
      throw ArgumentError.value(
        query.toString(),
        'query',
        'LSL predicates require at least one condition; a match-all query '
            'cannot be expressed',
      );
    }
    return compiled;
  }

  /// Returns null for a sub-query that imposes no constraint.
  static String? _compile(DiscoveryQuery query, {bool topLevel = false}) {
    switch (query) {
      case AlwaysMatch():
        return null;

      case FieldMatch(:final field, :final op, :final value):
        final path = _path(field);
        if (field == PeerField.randomRoll) {
          // Unquoted so XPath compares numerically, not lexicographically.
          final number = (value as num).toDouble();
          return switch (op) {
            MatchOp.lessThan => '$path < $number',
            MatchOp.greaterThan => '$path > $number',
            MatchOp.equals => '$path=$number',
            _ => throw ArgumentError('$op is not valid for randomRoll'),
          };
        }
        final literal = xpathLiteral(value as String);
        return switch (op) {
          MatchOp.equals => '$path=$literal',
          MatchOp.startsWith => 'starts-with($path, $literal)',
          MatchOp.endsWith => 'ends-with($path, $literal)',
          MatchOp.contains => 'contains($path, $literal)',
          MatchOp.lessThan => '$path < $literal',
          MatchOp.greaterThan => '$path > $literal',
        };

      case AndQuery(:final terms):
        final parts = terms
            .map((t) => _compile(t))
            .whereType<String>()
            .toList();
        if (parts.isEmpty) return null;
        if (parts.length == 1) return parts.single;
        // The top-level conjunction is unparenthesised, matching the original
        // builder's `conditions.join(' and ')`.
        final joined = parts.join(' and ');
        return topLevel ? joined : '($joined)';

      case OrQuery(:final terms):
        final parts = terms
            .map((t) => _compile(t))
            .whereType<String>()
            .toList();
        if (parts.isEmpty) {
          // An empty disjunction matches nothing. XPath has no false literal
          // that LSL reliably accepts, and silently dropping the term would
          // widen the query, so refuse.
          throw ArgumentError(
            'An empty OrQuery matches no peer and cannot be compiled to XPath',
          );
        }
        return '(${parts.join(' or ')})';

      case NotQuery(:final term):
        final inner = _compile(term);
        if (inner == null) {
          throw ArgumentError('not(match-all) matches no peer');
        }
        return 'not($inner)';
    }
  }
}
