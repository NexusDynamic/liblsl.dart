import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show StringUtf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// `lsl_push_chunk_*` — flat data buffer, all samples stamped "now".
typedef DartLSLPushChunk<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data, int dataElements);

/// `lsl_push_chunk_*t` — flat data buffer with one timestamp for the chunk
/// (0.0 means "now"; remaining samples are spaced by the sampling rate).
typedef DartLSLPushChunkT<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      double timestamp,
    );

/// `lsl_push_chunk_*tn` — flat data buffer with one timestamp per sample.
typedef DartLSLPushChunkTn<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      Pointer<Double> timestamps,
    );

/// `lsl_push_chunk_*tp` — as `*t`, with an explicit pushthrough flag.
typedef DartLSLPushChunkTP<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      double timestamp,
      int pushthrough,
    );

/// `lsl_push_chunk_*tnp` — as `*tn`, with an explicit pushthrough flag.
typedef DartLSLPushChunkTNP<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      Pointer<Double> timestamps,
      int pushthrough,
    );

/// The base class for chunk push operations, one subclass per channel format.
///
/// Data is a flat buffer of `sampleCount * channelCount` values in
/// sample-major order. For string streams each element is a pointer to a
/// NUL-terminated UTF-8 string (see [LSLPushChunkString]).
abstract class LSLPushChunk<T extends NativeType> {
  final DartLSLPushChunk<T> _push;
  final DartLSLPushChunkT<T> _pushT;
  final DartLSLPushChunkTn<T> _pushTn;
  final DartLSLPushChunkTP<T> _pushTP;
  final DartLSLPushChunkTNP<T> _pushTNP;

  const LSLPushChunk(
    this._push,
    this._pushT,
    this._pushTn,
    this._pushTP,
    this._pushTNP,
  );

  /// Pushes [elements] values stamped with the current time.
  int pushNow(lsl_outlet out, Pointer<NativeType> data, int elements) {
    return _push(out, data.cast(), elements);
  }

  /// Pushes [elements] values with a single [timestamp] (0.0 = now).
  ///
  /// A non-null [pushthrough] overrides the outlet's chunking for this push.
  int pushWithTimestamp(
    lsl_outlet out,
    Pointer<NativeType> data,
    int elements,
    double timestamp, {
    bool? pushthrough,
  }) {
    if (pushthrough != null) {
      return _pushTP(
        out,
        data.cast(),
        elements,
        timestamp,
        pushthrough ? 1 : 0,
      );
    }
    return _pushT(out, data.cast(), elements, timestamp);
  }

  /// Pushes [elements] values with one timestamp per sample.
  ///
  /// A non-null [pushthrough] overrides the outlet's chunking for this push.
  int pushWithTimestamps(
    lsl_outlet out,
    Pointer<NativeType> data,
    int elements,
    Pointer<Double> timestamps, {
    bool? pushthrough,
  }) {
    if (pushthrough != null) {
      return _pushTNP(
        out,
        data.cast(),
        elements,
        timestamps,
        pushthrough ? 1 : 0,
      );
    }
    return _pushTn(out, data.cast(), elements, timestamps);
  }

  /// Allocates a flat native buffer of [elements] values.
  Pointer<T> allocBuffer(int elements);

  /// Frees any per-element allocations [flatListToBuffer] made for the first
  /// [elements] values of [buffer].
  ///
  /// Only string chunks allocate per element; liblsl copies the data before
  /// the push returns, so this runs right after every push.
  void cleanupBuffer(Pointer<NativeType> buffer, int elements) {}

  /// Writes [flat] (length = elements) into [buffer] element-wise.
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer);

  /// Copies [elements] values from [src] into [buffer] (memmove).
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  );

  /// Whether [data] is the [TypedData] type matching this channel format.
  bool typedDataMatches(TypedData data);

  /// The expected [TypedData] type name, for error messages.
  String get typedDataName;
}

class LSLPushChunkFloat extends LSLPushChunk<Float> {
  const LSLPushChunkFloat()
    : super(
        lsl_push_chunk_f,
        lsl_push_chunk_ft,
        lsl_push_chunk_ftn,
        lsl_push_chunk_ftp,
        lsl_push_chunk_ftnp,
      );

  @override
  Pointer<Float> allocBuffer(int elements) => allocate<Float>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Float>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Float>().asTypedList(elements).setAll(0, src as Float32List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Float32List;

  @override
  String get typedDataName => 'Float32List';
}

class LSLPushChunkDouble extends LSLPushChunk<Double> {
  const LSLPushChunkDouble()
    : super(
        lsl_push_chunk_d,
        lsl_push_chunk_dt,
        lsl_push_chunk_dtn,
        lsl_push_chunk_dtp,
        lsl_push_chunk_dtnp,
      );

  @override
  Pointer<Double> allocBuffer(int elements) => allocate<Double>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Double>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Double>().asTypedList(elements).setAll(0, src as Float64List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Float64List;

  @override
  String get typedDataName => 'Float64List';
}

class LSLPushChunkInt8 extends LSLPushChunk<Char> {
  const LSLPushChunkInt8()
    : super(
        lsl_push_chunk_c,
        lsl_push_chunk_ct,
        lsl_push_chunk_ctn,
        lsl_push_chunk_ctp,
        lsl_push_chunk_ctnp,
      );

  @override
  Pointer<Char> allocBuffer(int elements) => allocate<Char>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Char>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int8>().asTypedList(elements).setAll(0, src as Int8List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int8List;

  @override
  String get typedDataName => 'Int8List';
}

class LSLPushChunkInt16 extends LSLPushChunk<Int16> {
  const LSLPushChunkInt16()
    : super(
        lsl_push_chunk_s,
        lsl_push_chunk_st,
        lsl_push_chunk_stn,
        lsl_push_chunk_stp,
        lsl_push_chunk_stnp,
      );

  @override
  Pointer<Int16> allocBuffer(int elements) => allocate<Int16>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int16>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int16>().asTypedList(elements).setAll(0, src as Int16List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int16List;

  @override
  String get typedDataName => 'Int16List';
}

class LSLPushChunkInt32 extends LSLPushChunk<Int32> {
  const LSLPushChunkInt32()
    : super(
        lsl_push_chunk_i,
        lsl_push_chunk_it,
        lsl_push_chunk_itn,
        lsl_push_chunk_itp,
        lsl_push_chunk_itnp,
      );

  @override
  Pointer<Int32> allocBuffer(int elements) => allocate<Int32>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int32>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int32>().asTypedList(elements).setAll(0, src as Int32List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int32List;

  @override
  String get typedDataName => 'Int32List';
}

class LSLPushChunkInt64 extends LSLPushChunk<Int64> {
  const LSLPushChunkInt64()
    : super(
        lsl_push_chunk_l,
        lsl_push_chunk_lt,
        lsl_push_chunk_ltn,
        lsl_push_chunk_ltp,
        lsl_push_chunk_ltnp,
      );

  @override
  Pointer<Int64> allocBuffer(int elements) => allocate<Int64>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int64>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int64>().asTypedList(elements).setAll(0, src as Int64List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int64List;

  @override
  String get typedDataName => 'Int64List';
}

/// Chunk push for string streams.
///
/// Each buffer element is a NUL-terminated UTF-8 copy of the Dart string,
/// allocated in [flatListToBuffer] and released by [cleanupBuffer]. Strings
/// containing NUL bytes need the binary API (`LSLOutlet.pushChunkBytes`).
/// There is no [TypedData] form of string data, so [typedDataMatches] is
/// always false.
class LSLPushChunkString extends LSLPushChunk<Pointer<Char>> {
  const LSLPushChunkString()
    : super(
        lsl_push_chunk_str,
        lsl_push_chunk_strt,
        lsl_push_chunk_strtn,
        lsl_push_chunk_strtp,
        lsl_push_chunk_strtnp,
      );

  @override
  Pointer<Pointer<Char>> allocBuffer(int elements) {
    final buffer = allocate<Pointer<Char>>(elements);
    // malloc does not zero memory; cleanupBuffer must be able to distinguish
    // "never written" entries from live allocations.
    for (int i = 0; i < elements; i++) {
      buffer[i] = nullPtr<Char>();
    }
    return buffer;
  }

  @override
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Pointer<Char>>();
    int i = 0;
    try {
      for (final value in flat) {
        typed[i++] = (value as String)
            .toNativeUtf8(allocator: allocate)
            .cast<Char>();
      }
    } catch (_) {
      // Release what was written so far; the caller never pushes.
      cleanupBuffer(buffer, i);
      rethrow;
    }
  }

  @override
  void cleanupBuffer(Pointer<NativeType> buffer, int elements) {
    final typed = buffer.cast<Pointer<Char>>();
    for (int i = 0; i < elements; i++) {
      if (!typed[i].isNullPointer) {
        typed[i].free();
        typed[i] = nullPtr<Char>();
      }
    }
  }

  @override
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    throw UnsupportedError('String chunks have no TypedData form');
  }

  @override
  bool typedDataMatches(TypedData data) => false;

  @override
  String get typedDataName => 'List<List<String>> (via pushChunk)';
}
