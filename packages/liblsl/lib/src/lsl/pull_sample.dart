import 'dart:ffi';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
import 'package:liblsl/src/meta/todo.dart';
import 'package:liblsl/src/util/reusable_buffer.dart';
import 'package:meta/meta.dart';

/// A function that pulls a sample from the inlet.
///
/// This is a generalized version of the lsl_pull_sample_* functions.
typedef DartLslPullSample<T extends NativeType> =
    double Function(
      lsl_inlet inlet,
      Pointer<T> buffer,
      int bufferSize,
      double timeout,
      Pointer<Int32> ec,
    );

@Todo('zeyus', 'Seperate the pointer alloc / native call from sample creation.')
/// The base class for all LSL pull sample types.
abstract class LslPullSample<T extends NativeType, D> {
  final DartLslPullSample<T> _pullFn;

  const LslPullSample(this._pullFn);

  @mustBeOverridden
  LSLSample<D> call(lsl_inlet inlet, int channels, double timeout);

  /// Allocates a sample buffer and calls the LSL pull function.
  /// @param [buffer] The buffer to store the sample.
  /// @param [inlet] The inlet to pull the sample from.
  /// @param [channels] The number of channels in the sample.
  /// @param [timeout] The timeout in seconds.
  /// @return [LSLSamplePointer] The sample pointer.
  LSLSamplePointer<T> pullSample(
    Pointer<T> buffer,
    lsl_inlet inlet,
    int channels,
    double timeout,
  ) {
    final Pointer<Int32> ec = allocate<Int32>();
    final double timestamp = _pullFn(inlet, buffer, channels, timeout, ec);
    final int errorCode = ec.value;
    if (LSLObj.error(errorCode)) {
      return LSLSamplePointer<T>(timestamp, errorCode, 0);
    }
    ec.free();
    return LSLSamplePointer<T>(timestamp, errorCode, buffer.address);
  }

  /// Pulls a sample into the provided reusable buffer.
  /// @param [buffer] The buffer / [LSLReusableBuffer.buffer] to store the
  ///         sample.
  /// @param [inlet] The inlet to pull the sample from.
  /// @param [channels] The number of channels in the sample.
  /// @param [timeout] The timeout in seconds.
  /// @return [LSLSample] The sample.
  /// @note This function is asynchronous and returns a [Future].
  /// @note The [buffer] must be allocated with the same number of channels
  ///       as the sample.
  /// @note The [buffer] must be freed after use.
  Future<LSLSamplePointer<T>> pullSampleInto(
    Pointer<T> buffer,
    lsl_inlet inlet,
    int channels,
    double timeout,
    Pointer<Int32> ec,
  ) async {
    final double timestamp = _pullFn(inlet, buffer, channels, timeout, ec);
    final int errorCode = ec.value;
    if (LSLObj.error(errorCode)) {
      return LSLSamplePointer<T>(timestamp, errorCode, 0);
    }
    return LSLSamplePointer<T>(timestamp, errorCode, buffer.address);
  }

  LSLSamplePointer<T> pullSampleIntoSync(
    Pointer<T> buffer,
    lsl_inlet inlet,
    int channels,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final double timestamp = _pullFn(inlet, buffer, channels, timeout, ec);
    final int errorCode = ec.value;
    if (LSLObj.error(errorCode)) {
      return LSLSamplePointer<T>(timestamp, errorCode, 0);
    }
    return LSLSamplePointer<T>(timestamp, errorCode, buffer.address);
  }

  @mustBeOverridden
  LSLReusableBuffer<T> createReusableBuffer(int channels) {
    throw UnimplementedError(
      'createReusableBuffer() must be implemented in subclass',
    );
  }

  @protected
  LSLSample<D> createSample(
    Pointer<T> buffer,
    lsl_inlet inlet,
    int channels,
    double timeout,
  ) {
    final Pointer<Int32> ec = allocate<Int32>();
    final double timestamp = _pullFn(inlet, buffer, channels, timeout, ec);
    final int errorCode = ec.value;
    if (LSLObj.error(errorCode)) {
      return LSLSample<D>(IList(), timestamp, errorCode);
    }
    ec.free();
    if (timestamp > 0) {
      final IList<D> result = bufferToList(buffer, channels);
      buffer.free();
      return LSLSample<D>(result, timestamp, errorCode);
    }
    buffer.free();
    return LSLSample<D>(IList(), timestamp, errorCode);
  }

  @mustBeOverridden
  IList<D> bufferToList(Pointer<T> buffer, int channels);

  @mustBeOverridden
  Pointer<T> allocBuffer(int channels);
}

/// Pulls a sample of type [Float] from the inlet and returns it as a list
/// of [double].
class LslPullSampleFloat extends LslPullSample<Float, double> {
  const LslPullSampleFloat() : super(lsl_pull_sample_f);

  @override
  IList<double> bufferToList(Pointer<Float> buffer, int channels) {
    return IList<double>(buffer.asTypedList(channels));
  }

  @override
  Pointer<Float> allocBuffer(int channels) {
    return allocate<Float>(channels);
  }

  @override
  LSLSample<double> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Float> buffer = allocate<Float>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Float> createReusableBuffer(int channels) {
    return LSLReusableBufferFloat(channels);
  }
}

/// Pulls a sample of type [Double] from the inlet and returns it as a list
/// of [double].
class LslPullSampleDouble extends LslPullSample<Double, double> {
  const LslPullSampleDouble() : super(lsl_pull_sample_d);

  @override
  IList<double> bufferToList(Pointer<Double> buffer, int channels) {
    return IList<double>(buffer.asTypedList(channels));
  }

  @override
  Pointer<Double> allocBuffer(int channels) {
    return allocate<Double>(channels);
  }

  @override
  LSLSample<double> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Double> buffer = allocate<Double>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Double> createReusableBuffer(int channels) {
    return LSLReusableBufferDouble(channels);
  }
}

/// Pulls a sample of type [Int8] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt8 extends LslPullSample<Char, int> {
  const LslPullSampleInt8() : super(lsl_pull_sample_c);
  @override
  IList<int> bufferToList(Pointer<Char> buffer, int channels) {
    return IList<int>(buffer.cast<Uint8>().asTypedList(channels));
  }

  @override
  Pointer<Char> allocBuffer(int channels) {
    return allocate<Char>(channels);
  }

  @override
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Char> buffer = allocate<Char>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Char> createReusableBuffer(int channels) {
    return LSLReusableBufferInt8(channels);
  }
}

/// Pulls a sample of type [Int16] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt16 extends LslPullSample<Int16, int> {
  const LslPullSampleInt16() : super(lsl_pull_sample_s);
  @override
  IList<int> bufferToList(Pointer<Int16> buffer, int channels) {
    return IList<int>(buffer.asTypedList(channels));
  }

  @override
  Pointer<Int16> allocBuffer(int channels) {
    return allocate<Int16>(channels);
  }

  @override
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int16> buffer = allocate<Int16>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Int16> createReusableBuffer(int channels) {
    return LSLReusableBufferInt16(channels);
  }
}

/// Pulls a sample of type [Int32] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt32 extends LslPullSample<Int32, int> {
  const LslPullSampleInt32() : super(lsl_pull_sample_i);
  @override
  IList<int> bufferToList(Pointer<Int32> buffer, int channels) {
    return IList<int>(buffer.asTypedList(channels));
  }

  @override
  Pointer<Int32> allocBuffer(int channels) {
    return allocate<Int32>(channels);
  }

  @override
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int32> buffer = allocate<Int32>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Int32> createReusableBuffer(int channels) {
    return LSLReusableBufferInt32(channels);
  }
}

/// Pulls a sample of type [Int64] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt64 extends LslPullSample<Int64, int> {
  const LslPullSampleInt64() : super(lsl_pull_sample_l);
  @override
  IList<int> bufferToList(Pointer<Int64> buffer, int channels) {
    return IList<int>(buffer.asTypedList(channels));
  }

  @override
  Pointer<Int64> allocBuffer(int channels) {
    return allocate<Int64>(channels);
  }

  @override
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int64> buffer = allocate<Int64>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Int64> createReusableBuffer(int channels) {
    return LSLReusableBufferInt64(channels);
  }
}

/// Pulls a sample of type [String] from the inlet and returns it as a list
/// of [String].
class LslPullSampleString extends LslPullSample<Pointer<Char>, String> {
  const LslPullSampleString() : super(lsl_pull_sample_str);
  @override
  IList<String> bufferToList(Pointer<Pointer<Char>> buffer, int channels) {
    return IList<String>(
      List<String>.generate(
        channels,
        (index) => buffer[index].cast<Utf8>().toDartString(),
        growable: false,
      ),
    );
  }

  @override
  Pointer<Pointer<Char>> allocBuffer(int channels) {
    return allocate<Pointer<Char>>(channels);
  }

  @override
  LSLSample<String> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Pointer<Char>> buffer = allocate<Pointer<Char>>(channels);
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Pointer<Char>> createReusableBuffer(int channels) {
    return LSLReusableBufferString(channels);
  }
}

/// Pulls a sample of type [Void] from the inlet and returns it as a list
/// of [Null].
class LslPullSampleUndefined extends LslPullSample<Void, Null> {
  const LslPullSampleUndefined() : super(lsl_pull_sample_v);
  @override
  IList<Null> bufferToList(Pointer<Void> buffer, int channels) {
    return IList<Null>(List<Null>.filled(channels, null, growable: false));
  }

  @override
  Pointer<Void> allocBuffer(int channels) {
    return nullPtr<Void>();
  }

  @Todo('zeyus', 'Confirm void sample creation works, add to tests.')
  @override
  LSLSample<Null> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Void> buffer = nullPtr<Void>();
    return createSample(buffer, inlet, channels, timeout);
  }

  @override
  LSLReusableBuffer<Void> createReusableBuffer(int channels) {
    return LSLReusableBufferVoid(channels);
  }
}
