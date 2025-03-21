class LSLSample<T> {
  final List<T> data;
  final double timestamp;
  final int errorCode;

  LSLSample(this.data, this.timestamp, this.errorCode);
}
