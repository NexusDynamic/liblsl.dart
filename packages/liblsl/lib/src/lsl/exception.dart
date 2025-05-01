/// LSLException base exception class
class LSLException implements Exception {
  final String message;

  /// Creates a new LSLException with the given message.
  /// The [message] parameter is used to create the exception message.
  LSLException(this.message);

  @override
  String toString() {
    return 'LSLException: $message';
  }
}

/// LSLTimeout exception class
class LSLTimeout extends LSLException {
  LSLTimeout(super.message);

  @override
  String toString() {
    return 'LSLTimeout: $message';
  }
}
