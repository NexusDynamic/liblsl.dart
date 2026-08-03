import 'dart:ffi';
import 'package:ffi/ffi.dart' show Utf8, StringUtf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/util/reusable_buffer.dart';
import 'package:meta/meta.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Generalized description of the lsl_push_sample_* functions.
typedef DartLSLPushSample<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data);

/// The base class for all LSL push sample types.
abstract class LSLPushSample<T extends NativeType> {
  final DartLSLPushSample<T> _pushFn;

  const LSLPushSample(this._pushFn);

  int call(lsl_outlet out, Pointer<T> data) {
    return _pushFn(out, data);
  }

  /// Maybe this isn't needed because the ec is allocated but unused for push.
  @mustBeOverridden
  LSLReusableBuffer<T> createReusableBuffer(int channels) {
    throw UnimplementedError(
      'createReusableBuffer() must be implemented in subclass',
    );
  }

  /// Allocates a buffer of the given type.
  /// @note this does NO checking if the buffer allocation was successful.
  @mustBeOverridden
  Pointer<T> allocBuffer(int channels);

  @mustBeOverridden
  void listToBuffer(Iterable<dynamic> samples, Pointer<T> buffer);

  /// Frees any per-element allocations made by [listToBuffer].
  ///
  /// Most formats write values directly into [buffer] and need no cleanup;
  /// only string samples allocate a native UTF-8 copy per element, which must
  /// be released once the push call has returned (liblsl copies the data
  /// before returning).
  void cleanupBuffer(Pointer<T> buffer, int count) {}
}

/// Push sample for float32 data.
class LSLPushSampleFloat extends LSLPushSample<Float> {
  const LSLPushSampleFloat() : super(lsl_push_sample_f);

  @override
  LSLReusableBuffer<Float> createReusableBuffer(int channels) {
    return LSLReusableBufferFloat(channels);
  }

  @override
  Pointer<Float> allocBuffer(int channels) {
    return allocate<Float>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Float> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for double64 data.
class LSLPushSampleDouble extends LSLPushSample<Double> {
  const LSLPushSampleDouble() : super(lsl_push_sample_d);

  @override
  LSLReusableBuffer<Double> createReusableBuffer(int channels) {
    return LSLReusableBufferDouble(channels);
  }

  @override
  Pointer<Double> allocBuffer(int channels) {
    return allocate<Double>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Double> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for int8 data.
class LSLPushSampleInt8 extends LSLPushSample<Char> {
  const LSLPushSampleInt8() : super(lsl_push_sample_c);

  @override
  LSLReusableBuffer<Char> createReusableBuffer(int channels) {
    return LSLReusableBufferInt8(channels);
  }

  @override
  Pointer<Char> allocBuffer(int channels) {
    return allocate<Char>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Char> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for int16 data.
class LSLPushSampleInt16 extends LSLPushSample<Int16> {
  const LSLPushSampleInt16() : super(lsl_push_sample_s);

  @override
  LSLReusableBuffer<Int16> createReusableBuffer(int channels) {
    return LSLReusableBufferInt16(channels);
  }

  @override
  Pointer<Int16> allocBuffer(int channels) {
    return allocate<Int16>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Int16> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for int32 data.
class LSLPushSampleInt32 extends LSLPushSample<Int32> {
  const LSLPushSampleInt32() : super(lsl_push_sample_i);

  @override
  LSLReusableBuffer<Int32> createReusableBuffer(int channels) {
    return LSLReusableBufferInt32(channels);
  }

  @override
  Pointer<Int32> allocBuffer(int channels) {
    return allocate<Int32>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Int32> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for int64 data.
class LSLPushSampleInt64 extends LSLPushSample<Int64> {
  const LSLPushSampleInt64() : super(lsl_push_sample_l);

  @override
  LSLReusableBuffer<Int64> createReusableBuffer(int channels) {
    return LSLReusableBufferInt64(channels);
  }

  @override
  Pointer<Int64> allocBuffer(int channels) {
    return allocate<Int64>(channels);
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Int64> buffer) {
    int i = 0;
    for (final value in samples) {
      buffer[i++] = value;
    }
  }
}

/// Push sample for string data.
class LSLPushSampleString extends LSLPushSample<Pointer<Char>> {
  const LSLPushSampleString() : super(lsl_push_sample_str);

  @override
  LSLReusableBuffer<Pointer<Char>> createReusableBuffer(int channels) {
    return LSLReusableBufferString(channels);
  }

  @override
  Pointer<Pointer<Char>> allocBuffer(int channels) {
    final buffer = allocate<Pointer<Char>>(channels);
    // malloc does not zero memory; cleanupBuffer must be able to distinguish
    // "never written" entries from live allocations.
    for (int i = 0; i < channels; i++) {
      buffer[i] = nullPtr<Char>();
    }
    return buffer;
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Pointer<Char>> buffer) {
    // Free any strings left from a previous fill that was never pushed.
    cleanupBuffer(buffer, samples.length);
    int i = 0;
    for (final value in samples) {
      final Pointer<Utf8> utf8String = (value as String).toNativeUtf8(
        allocator: allocate,
      );
      buffer[i++] = utf8String.cast<Char>();
    }
  }

  @override
  void cleanupBuffer(Pointer<Pointer<Char>> buffer, int count) {
    for (int i = 0; i < count; i++) {
      if (!buffer[i].isNullPointer) {
        buffer[i].free();
        buffer[i] = nullPtr<Char>();
      }
    }
  }
}

/// Push sample for void data.
class LSLPushSampleVoid extends LSLPushSample<Void> {
  const LSLPushSampleVoid() : super(lsl_push_sample_v);

  @override
  LSLReusableBuffer<Void> createReusableBuffer(int channels) {
    return LSLReusableBufferVoid(channels);
  }

  @override
  Pointer<Void> allocBuffer(int channels) {
    return nullPtr<Void>();
  }

  @override
  @pragma('vm:prefer-inline')
  void listToBuffer(Iterable<dynamic> samples, Pointer<Void> buffer) {
    // No-op for void type
  }
}
