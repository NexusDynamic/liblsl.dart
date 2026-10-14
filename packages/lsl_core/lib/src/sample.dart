import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A representation of a sample.
///
/// This class represents both samples pulled from an inlet, and in future
/// versions, samples pushed to an outlet.
class LSLSample<T> {
  final IList<T> data;
  final double timestamp;
  final int errorCode;

  const LSLSample(this.data, this.timestamp, this.errorCode);

  T operator [](int index) {
    return data[index];
  }

  int get length {
    return data.length;
  }

  bool get isEmpty {
    return data.isEmpty;
  }

  bool get isNotEmpty {
    return data.isNotEmpty;
  }

  @override
  String toString() {
    return 'LSLSample{data: $data, timestamp: $timestamp, errorCode: $errorCode}';
  }
}
