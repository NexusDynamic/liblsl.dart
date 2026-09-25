@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show calloc;
import 'package:liblsl/lsl.dart';
import 'package:test/test.dart';

/// `struct rlimit`: two 64-bit `rlim_t` values on 64-bit macOS and Linux.
typedef _GetRLimitNative = Int32 Function(Int32, Pointer<Uint64>);
typedef _GetRLimit = int Function(int, Pointer<Uint64>);

/// The process's (soft, hard) open-file limit.
(int, int) _openFileLimit() {
  final getrlimit = DynamicLibrary.process()
      .lookupFunction<_GetRLimitNative, _GetRLimit>('getrlimit');
  final rlimitNoFile = Platform.isMacOS ? 8 : 7; // RLIMIT_NOFILE
  final limit = calloc<Uint64>(2);
  try {
    expect(getrlimit(rlimitNoFile, limit), 0);
    return (limit[0], limit[1]);
  } finally {
    calloc.free(limit);
  }
}

void main() {
  test('loading liblsl raises the soft open-file limit', () {
    // Any call loads the library, whose constructor raises the limit
    // (src/dart/fd_limit.cpp).
    expect(LSL.version, greaterThan(0));
    final (soft, hard) = _openFileLimit();
    // At least 4096 (or the hard limit, if lower); well above the defaults
    // (256 on macOS, 1024 on Linux). rlim_t is unsigned, so RLIM_INFINITY
    // reads back as -1 here.
    final floor = hard < 0 || hard > 4096 ? 4096 : hard;
    expect(
      soft < 0 || soft >= floor,
      isTrue,
      reason: 'soft limit $soft, hard limit $hard',
    );
  });
}
