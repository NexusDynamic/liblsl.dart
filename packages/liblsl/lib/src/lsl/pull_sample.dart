import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer, calloc;
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
abstract class LslPullSample<T extends NativeType, D> {
  final DartLslPullSample<T> _pullFn;

  const LslPullSample(this._pullFn);

  @mustBeOverridden
  LSLSample<D> call(lsl_inlet inlet, int channels, double timeout);

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
    final List<D> result = bufferToList(buffer, channels);
    buffer.free();
    return LSLSample<D>(result, timestamp, errorCode);
  }

  @mustBeOverridden
  List<D> bufferToList(Pointer<T> buffer, int channels);
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
  LSLSample<double> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Float> buffer = calloc<Float>(channels);
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
  LSLSample<double> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Double> buffer = calloc<Double>(channels);
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
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Char> buffer = calloc<Char>(channels);
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
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int16> buffer = calloc<Int16>(channels);
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
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int32> buffer = calloc<Int32>(channels);
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
  LSLSample<int> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Int64> buffer = calloc<Int64>(channels);
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
  LSLSample<String> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Pointer<Char>> buffer = calloc<Pointer<Char>>(channels);
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

  // @TODO: Check out if this is right with the Void alloc...maybe it needs a
  // length?
  @override
  LSLSample<Null> call(lsl_inlet inlet, int channels, double timeout) {
    final Pointer<Void> buffer = nullPtr<Void>();
    return createSample(buffer, inlet, channels, timeout);
  }
}
