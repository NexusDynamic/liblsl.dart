import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
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
    Pointer<T> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  );
}

/// Pulls a sample of type [Float] from the inlet and returns it as a list
/// of [double].
class LslPullSampleFloat extends LslPullSample<Float, double> {
  const LslPullSampleFloat(super._pullFn);

  @override
  LSLSample<double> call(
    lsl_inlet inlet,
    Pointer<Float> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleDouble(super._pullFn);

  @override
  LSLSample<double> call(
    lsl_inlet inlet,
    Pointer<Double> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleInt8(super._pullFn);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    Pointer<Char> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleInt16(super._pullFn);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    Pointer<Int16> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleInt32(super._pullFn);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    Pointer<Int32> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleInt64(super._pullFn);

  @override
  LSLSample<int> call(
    lsl_inlet inlet,
    Pointer<Int64> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleString(super._pullFn);

  @override
  LSLSample<String> call(
    lsl_inlet inlet,
    Pointer<Pointer<Char>> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
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
  const LslPullSampleUndefined(super._pullFn);

  @override
  LSLSample<Null> call(
    lsl_inlet inlet,
    Pointer<Void> buffer,
    int bufferSize,
    double timeout,
    Pointer<Int32> ec,
  ) {
    final double timestamp = _pullFn(inlet, buffer, bufferSize, timeout, ec);
    final int errorCode = ec.value;
    return LSLSample<Null>([], timestamp, errorCode);
  }
}
