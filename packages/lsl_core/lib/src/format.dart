/// The stream info channel formats.
///
/// The FFI side of a format (`lslFormat`, `ffiType`, `dartType`) is an
/// extension in `package:liblsl`.
enum LSLChannelFormat {
  float32,
  double64,
  int8,
  int16,
  int32,
  int64,
  string,
  undefined;

  bool get isString => this == string;

  bool get isInteger => switch (this) {
    int8 || int16 || int32 || int64 => true,
    _ => false,
  };

  /// Bytes per value; 0 for [string] and [undefined].
  int get byteWidth => switch (this) {
    float32 => 4,
    double64 => 8,
    int8 => 1,
    int16 => 2,
    int32 => 4,
    int64 => 8,
    string || undefined => 0,
  };

  /// The format an outlet of this format is made with: [undefined] has no
  /// outlet of its own, so it is float32.
  LSLChannelFormat get outletFormat => this == undefined ? float32 : this;

  /// The format named [name] in a stream's info (`channel_format`). Some
  /// writers use "double" and "float".
  static LSLChannelFormat parse(String name) {
    final n = name.trim().toLowerCase();
    for (final f in values) {
      if (f.name == n) return f;
    }
    if (n == 'double') return double64;
    if (n == 'float') return float32;
    throw FormatException('Unknown channel format "$name"');
  }
}
