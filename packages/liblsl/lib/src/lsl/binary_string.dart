import 'dart:ffi';
import 'dart:typed_data';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Native buffers for one binary-string (`lsl_*_buf`) transfer.
///
/// Binary strings are length-prefixed rather than NUL-terminated, so they
/// may contain `0x00` bytes. Each element is a `char*` plus a `uint32`
/// length. The buffers are allocated per call and released with [free];
/// isolated mode passes their addresses to the worker, which only reads or
/// writes them while the owning isolate is awaiting its response.
final class LSLBinaryBuffer {
  /// Number of string elements (`samples * channels`).
  final int elements;

  final Pointer<Pointer<Char>> data;
  final Pointer<Uint32> lengths;

  /// Per-sample timestamps; [nullptr] when not requested.
  final Pointer<Double> timestamps;

  final Pointer<Int32> ec;

  /// Whether the strings in [data] were allocated by liblsl (pull) rather
  /// than by us (push); decides how they are released.
  final bool _liblslOwned;

  LSLBinaryBuffer._(
    this.elements,
    this.data,
    this.lengths,
    this.timestamps,
    this.ec,
    this._liblslOwned,
  );

  static LSLBinaryBuffer _alloc(int elements, int timestampCount, bool pull) {
    final data = allocate<Pointer<Char>>(elements);
    for (int i = 0; i < elements; i++) {
      data[i] = nullPtr<Char>();
    }
    return LSLBinaryBuffer._(
      elements,
      data,
      allocate<Uint32>(elements),
      timestampCount > 0 ? allocate<Double>(timestampCount) : nullptr,
      allocate<Int32>(),
      pull,
    );
  }

  /// Allocates buffers holding a native copy of each of [values].
  factory LSLBinaryBuffer.forPush(
    Iterable<Uint8List> values, {
    int timestampCount = 0,
  }) {
    final buf = _alloc(values.length, timestampCount, false);
    int i = 0;
    for (final value in values) {
      // Always allocate at least one byte so an empty value is still a live
      // pointer; its length stays 0.
      final ptr = allocate<Uint8>(value.isEmpty ? 1 : value.length);
      ptr.asTypedList(value.length).setAll(0, value);
      buf.data[i] = ptr.cast<Char>();
      buf.lengths[i] = value.length;
      i++;
    }
    return buf;
  }

  /// Allocates empty buffers for liblsl to fill.
  factory LSLBinaryBuffer.forPull(int elements, {int timestampCount = 0}) =>
      _alloc(elements, timestampCount, true);

  /// The buffer addresses, for handing to a worker isolate.
  Map<String, int> get addresses => {
    'elements': elements,
    'data': data.address,
    'lengths': lengths.address,
    'timestamps': timestamps.address,
    'ec': ec.address,
  };

  /// A non-owning view of buffers described by [addresses], for use in the
  /// worker isolate. Never [free] a view; the owning isolate does that.
  factory LSLBinaryBuffer.view(Map<String, dynamic> addresses) =>
      LSLBinaryBuffer._(
        addresses['elements'] as int,
        Pointer<Pointer<Char>>.fromAddress(addresses['data'] as int),
        Pointer<Uint32>.fromAddress(addresses['lengths'] as int),
        Pointer<Double>.fromAddress(addresses['timestamps'] as int),
        Pointer<Int32>.fromAddress(addresses['ec'] as int),
        false,
      );

  /// Copies the first [count] elements out as [Uint8List]s.
  List<Uint8List> read(int count) => List<Uint8List>.generate(count, (i) {
    final ptr = data[i];
    final length = lengths[i];
    if (ptr.isNullPointer || length == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(ptr.cast<Uint8>().asTypedList(length));
  }, growable: false);

  /// Releases every per-element string still held in [data].
  ///
  /// After a successful pull liblsl has allocated *all* slots it was given
  /// (not only those it filled), so this walks the whole buffer. After a
  /// failed pull liblsl has already released its allocations, so
  /// [discardStrings] must be used instead.
  void releaseStrings() {
    for (int i = 0; i < elements; i++) {
      final ptr = data[i];
      if (!ptr.isNullPointer) {
        if (_liblslOwned) {
          lsl_destroy_string(ptr);
        } else {
          ptr.free();
        }
        data[i] = nullPtr<Char>();
      }
    }
  }

  /// Forgets the element pointers without freeing them (see
  /// [releaseStrings]).
  void discardStrings() {
    for (int i = 0; i < elements; i++) {
      data[i] = nullPtr<Char>();
    }
  }

  /// Releases the strings and all buffers.
  void free() {
    releaseStrings();
    data.free();
    lengths.free();
    if (!timestamps.isNullPointer) {
      timestamps.free();
    }
    ec.free();
  }
}

/// Pushes one binary sample via `lsl_push_sample_buf{,t,tp}`.
int lslPushSampleBinary(
  lsl_outlet out,
  Pointer<Pointer<Char>> data,
  Pointer<Uint32> lengths, {
  double? timestamp,
  bool? pushthrough,
}) {
  if (pushthrough != null) {
    return lsl_push_sample_buftp(
      out,
      data,
      lengths,
      timestamp ?? 0.0,
      pushthrough ? 1 : 0,
    );
  }
  if (timestamp != null) {
    return lsl_push_sample_buft(out, data, lengths, timestamp);
  }
  return lsl_push_sample_buf(out, data, lengths);
}

/// Pushes [elements] binary values via `lsl_push_chunk_buf{,t,tn,tp,tnp}`.
///
/// [timestamps], when given, holds one timestamp per sample and takes
/// precedence over [timestamp].
int lslPushChunkBinary(
  lsl_outlet out,
  Pointer<Pointer<Char>> data,
  Pointer<Uint32> lengths,
  int elements, {
  double? timestamp,
  Pointer<Double>? timestamps,
  bool? pushthrough,
}) {
  if (timestamps != null) {
    return pushthrough != null
        ? lsl_push_chunk_buftnp(
            out,
            data,
            lengths,
            elements,
            timestamps,
            pushthrough ? 1 : 0,
          )
        : lsl_push_chunk_buftn(out, data, lengths, elements, timestamps);
  }
  if (pushthrough != null) {
    return lsl_push_chunk_buftp(
      out,
      data,
      lengths,
      elements,
      timestamp ?? 0.0,
      pushthrough ? 1 : 0,
    );
  }
  if (timestamp != null) {
    return lsl_push_chunk_buft(out, data, lengths, elements, timestamp);
  }
  return lsl_push_chunk_buf(out, data, lengths, elements);
}

/// Pulls one binary sample into [buf] via `lsl_pull_sample_buf`; returns
/// its timestamp (0.0 on timeout). Error code is left in `buf.ec`.
double lslPullSampleBinary(
  lsl_inlet inlet,
  LSLBinaryBuffer buf,
  double timeout,
) => lsl_pull_sample_buf(
  inlet,
  buf.data,
  buf.lengths,
  buf.elements,
  timeout,
  buf.ec,
);

/// Pulls up to `buf.elements / channels` binary samples into [buf] via
/// `lsl_pull_chunk_buf`; returns the number of data elements written.
int lslPullChunkBinary(
  lsl_inlet inlet,
  LSLBinaryBuffer buf,
  int channels,
  double timeout,
) => lsl_pull_chunk_buf(
  inlet,
  buf.data,
  buf.lengths,
  buf.timestamps,
  buf.elements,
  buf.elements ~/ channels,
  timeout,
  buf.ec,
);
