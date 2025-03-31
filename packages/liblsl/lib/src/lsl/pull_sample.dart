import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
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

/// The base class for all LSL pull sample types.
/// @TODO: Seperate the pointer alloc / native call from the sample creation.
/// This prevents duplicating and sending objects between threads if we can
/// just use a pointer instead.
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
      return LSLSample<D>([], timestamp, errorCode);
    }
    ec.free();
    if (timestamp > 0) {
      final List<D> result = bufferToList(buffer, channels);
      buffer.free();
      return LSLSample<D>(result, timestamp, errorCode);
    }
    buffer.free();
    return LSLSample<D>([], timestamp, errorCode);
  }

  @mustBeOverridden
  List<D> bufferToList(Pointer<T> buffer, int channels);

  @mustBeOverridden
  Pointer<T> allocBuffer(int channels);
}

/// Pulls a sample of type [Float] from the inlet and returns it as a list
/// of [double].
class LslPullSampleFloat extends LslPullSample<Float, double> {
  const LslPullSampleFloat() : super(lsl_pull_sample_f);

  @override
  List<double> bufferToList(Pointer<Float> buffer, int channels) {
    final List<double> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i]);
    }
    return result;
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
}

/// Pulls a sample of type [Double] from the inlet and returns it as a list
/// of [double].
class LslPullSampleDouble extends LslPullSample<Double, double> {
  const LslPullSampleDouble() : super(lsl_pull_sample_d);

  @override
  List<double> bufferToList(Pointer<Double> buffer, int channels) {
    final List<double> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i]);
    }
    return result;
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
}

/// Pulls a sample of type [Int8] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt8 extends LslPullSample<Char, int> {
  const LslPullSampleInt8() : super(lsl_pull_sample_c);
  @override
  List<int> bufferToList(Pointer<Char> buffer, int channels) {
    final List<int> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i]);
    }
    return result;
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
}

/// Pulls a sample of type [Int16] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt16 extends LslPullSample<Int16, int> {
  const LslPullSampleInt16() : super(lsl_pull_sample_s);
  @override
  List<int> bufferToList(Pointer<Int16> buffer, int channels) {
    final List<int> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i].toInt());
    }
    return result;
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
}

/// Pulls a sample of type [Int32] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt32 extends LslPullSample<Int32, int> {
  const LslPullSampleInt32() : super(lsl_pull_sample_i);
  @override
  List<int> bufferToList(Pointer<Int32> buffer, int channels) {
    final List<int> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i].toInt());
    }
    return result;
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
}

/// Pulls a sample of type [Int64] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt64 extends LslPullSample<Int64, int> {
  const LslPullSampleInt64() : super(lsl_pull_sample_l);
  @override
  List<int> bufferToList(Pointer<Int64> buffer, int channels) {
    final List<int> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i].toInt());
    }
    return result;
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
}

/// Pulls a sample of type [String] from the inlet and returns it as a list
/// of [String].
class LslPullSampleString extends LslPullSample<Pointer<Char>, String> {
  const LslPullSampleString() : super(lsl_pull_sample_str);
  @override
  List<String> bufferToList(Pointer<Pointer<Char>> buffer, int channels) {
    final List<String> result = [];
    for (int i = 0; i < channels; i++) {
      result.add(buffer[i].cast<Utf8>().toDartString());
    }

    return result;
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
}

/// Pulls a sample of type [Void] from the inlet and returns it as a list
/// of [Null].
class LslPullSampleUndefined extends LslPullSample<Void, Null> {
  const LslPullSampleUndefined() : super(lsl_pull_sample_v);
  @override
  List<Null> bufferToList(Pointer<Void> buffer, int channels) {
    return List<Null>.filled(channels, null);
  }

  @override
  Pointer<Void> allocBuffer(int channels) {
    return nullPtr<Void>();
  }

  // @TODO: Check out if this is right with the Void alloc...maybe it needs a
  // length?
  @override
  LSLSample<Null> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Void> buffer = nullPtr<Void>();
    return createSample(buffer, inlet, channels, timeout);
  }
}
