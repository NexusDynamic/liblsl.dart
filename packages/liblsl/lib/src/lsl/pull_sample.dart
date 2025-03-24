import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;

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
abstract class LslPullSample<T extends NativeType, D> {
  final DartLslPullSample<T> _pullFn;

  const LslPullSample(this._pullFn);

  LSLSample<D> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  );
}

/// Pulls a sample of type [Float] from the inlet and returns it as a list
/// of [double].
class LslPullSampleFloat extends LslPullSample<Float, double> {
  const LslPullSampleFloat() : super(lsl_pull_sample_f);

  @override
  LSLSample<double> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Float> buffer = allocate<Float>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<double> result = [];
    if (LSLObj.error(ec.value)) {
      return LSLSample<double>(result, timestamp, errorCode);
    }
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<double>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Double] from the inlet and returns it as a list
/// of [double].
class LslPullSampleDouble extends LslPullSample<Double, double> {
  const LslPullSampleDouble() : super(lsl_pull_sample_d);

  @override
  LSLSample<double> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Double> buffer = allocate<Double>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<double> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<double>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Int8] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt8 extends LslPullSample<Char, int> {
  const LslPullSampleInt8() : super(lsl_pull_sample_c);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Char> buffer = allocate<Char>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<int> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<int>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Int16] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt16 extends LslPullSample<Int16, int> {
  const LslPullSampleInt16() : super(lsl_pull_sample_s);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Int16> buffer = allocate<Int16>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<int> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<int>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Int32] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt32 extends LslPullSample<Int32, int> {
  const LslPullSampleInt32() : super(lsl_pull_sample_i);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Int32> buffer = allocate<Int32>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<int> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<int>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Int64] from the inlet and returns it as a list
/// of [int].
class LslPullSampleInt64 extends LslPullSample<Int64, int> {
  const LslPullSampleInt64() : super(lsl_pull_sample_l);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Int64> buffer = allocate<Int64>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<int> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i]);
    }
    return LSLSample<int>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [String] from the inlet and returns it as a list
/// of [String].
class LslPullSampleString extends LslPullSample<Pointer<Char>, String> {
  const LslPullSampleString() : super(lsl_pull_sample_str);

  @override
  LSLSample<String> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Pointer<Char>> buffer = allocate<Pointer<Char>>(channels);
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    final List<String> result = [];
    for (int i = 0; i < bufferSize; i++) {
      result.add(buffer[i].cast<Utf8>().toDartString());
    }
    return LSLSample<String>(result, timestamp, errorCode);
  }
}

/// Pulls a sample of type [Void] from the inlet and returns it as a list
/// of [Null].
class LslPullSampleUndefined extends LslPullSample<Void, Null> {
  const LslPullSampleUndefined() : super(lsl_pull_sample_v);

  @override
  LSLSample<Null> call(
    lsl_inlet inlet,
    int channels,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final Pointer<Void> buffer = nullPtr<Void>();
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    return LSLSample<Null>(
      List.generate(channels, (index) => null),
      timestamp,
      errorCode,
    );
  }
}
