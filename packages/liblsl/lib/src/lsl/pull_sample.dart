import 'dart:ffi';
import 'package:liblsl/liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;

typedef DartLslPullSample<T extends NativeType> =
    double Function(
      lsl_inlet inlet,
      Pointer<T> buffer,
      int bufferSize,
      double timeout,
      Pointer<Int32> ec,
    );

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
