class LSLException implements Exception {
  final String message;

  LSLException(this.message);

  @override
  String toString() {
    return 'LSLException: $message';
  }
}
