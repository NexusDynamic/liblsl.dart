class LSLException implements Exception {
  final String message;

  LSLException(this.message);

  @override
  String toString() {
    return 'LSLException: $message';
  }
}

class LSLTimeout extends LSLException {
  LSLTimeout(super.message);

  @override
  String toString() {
    return 'LSLTimeout: $message';
  }
}
