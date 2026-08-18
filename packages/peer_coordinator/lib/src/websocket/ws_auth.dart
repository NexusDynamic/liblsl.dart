/// The hub's authentication primitives.
///
/// Web-safe by construction: `package:crypto` and `dart:math` both compile to
/// JavaScript, so a browser node can authenticate with the same code the hub
/// verifies against. Nothing here touches `dart:io`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// WebSocket close codes the hub uses to say *why* it hung up.
///
/// In the application-private 4000-4999 range. A client that cannot tell
/// "your credentials are wrong" from "the session is over" from "the network
/// blipped" will retry when it should stop, or stop when it should retry.
abstract final class HubCloseCode {
  /// Authentication failed, or a frame arrived before authentication.
  static const int unauthorized = 4401;

  /// The session has ended, or this node was revoked. Do not retry.
  static const int sessionClosed = 4403;

  /// The claimed endpoint or identity belongs to another live connection.
  static const int identityConflict = 4409;

  /// A limit was exceeded: frame too large, too many endpoints, too many
  /// queries, hub full.
  static const int policyViolation = 4413;
}

/// The shared secret for one hub session.
///
/// The secret is never transmitted — it is the HMAC key at both ends — so this
/// holds up on plain `ws://`. TLS still matters for the confidentiality of
/// session *traffic*, but not for protecting the credential.
class HubCredentials {
  HubCredentials({required this.session, required this.secret}) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must not be empty');
    }
    if (secret.isEmpty) {
      throw ArgumentError.value('<redacted>', 'secret', 'must not be empty');
    }
  }

  /// The session name. Bound into the proof, and checked against every
  /// descriptor a peer publishes, so one hub is one session.
  final String session;

  /// The shared secret. Never sent over the wire and never logged.
  final String secret;

  /// Generates a secret suitable for handing to participants.
  ///
  /// 32 bytes of [Random.secure] as url-safe base64.
  static String generateSecret() => base64Url.encode(_randomBytes(32));

  /// A fresh single-use challenge nonce.
  static String newNonce() => base64.encode(_randomBytes(32));

  /// The proof a client sends and the hub recomputes.
  ///
  /// The nonce makes it single-use, [session] and [epoch] bind it to *this*
  /// session generation — so ending a session invalidates every outstanding
  /// proof — and [nodeUId] binds it to the identity the peer then publishes
  /// descriptors under, which is what stops one authenticated peer claiming
  /// another's endpoints.
  static String computeProof({
    required String secret,
    required String nonce,
    required String session,
    required int epoch,
    required String nodeUId,
  }) => base64.encode(
    Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode('$nonce|$session|$epoch|$nodeUId')).bytes,
  );

  /// Length-independent, content-constant-time comparison.
  ///
  /// A plain `==` on the proof leaks how many leading bytes matched through
  /// timing, which is enough to forge one byte at a time.
  static bool secureEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    // Both proofs are fixed-width base64 digests, so the length is not itself
    // a secret — but folding it into `diff` rather than returning early keeps
    // the content comparison unconditional.
    var diff = x.length ^ y.length;
    final length = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  /// Never renders the secret.
  @override
  String toString() => 'HubCredentials(session: $session, secret: <redacted>)';

  static List<int> _randomBytes(int count) {
    final random = Random.secure();
    return [for (var i = 0; i < count; i++) random.nextInt(256)];
  }
}
