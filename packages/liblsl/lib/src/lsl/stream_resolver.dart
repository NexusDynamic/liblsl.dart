import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Represents a property of an LSL stream that can be used for filtering.
/// This enum is used in [LSLStreamResolver] to filter streams by their
/// properties.
enum LSLStreamProperty {
  name(lslName: 'name'),
  type(lslName: 'type'),
  channelCount(lslName: 'channel_count'),
  channelFormat(lslName: 'channel_format'),
  sourceId(lslName: 'source_id'),
  sampleRate(lslName: 'nominal_srate');

  const LSLStreamProperty({required this.lslName});
  final String lslName;
}

/// The standard resolver for LSL streams.
class LSLStreamResolver extends LSLObj {
  int maxStreams;
  Pointer<lsl_streaminfo>? _streamInfoBuffer;

  /// Creates a new LSLStreamResolver object.
  /// The [maxStreams] parameter determines the maximum number of streams
  /// to resolve, ideally, this would be the exact number of streams you expect
  /// to be available.
  LSLStreamResolver({this.maxStreams = 5}) {
    if (maxStreams <= 0) {
      throw LSLException('maxStreams must be greater than 0');
    }
  }

  @override

  /// Creates the resolver and allocates the stream info buffer.
  LSLStreamResolver create() {
    if (created) {
      throw LSLException('Resolver already created');
    }
    _streamInfoBuffer = allocate<lsl_streaminfo>(maxStreams);
    super.create();
    return this;
  }

  /// Resolves streams available on the network.
  /// The [waitTime] parameter determines how long to wait for streams to
  /// resolve.
  /// It is your responsibility to ensure that the returned streams are
  /// destroyed when no longer needed.
  Future<List<LSLStreamInfo>> resolve({double waitTime = 5.0}) async {
    if (!created) {
      throw LSLException('Resolver not created');
    }
    final streamCount = lsl_resolve_all(
      _streamInfoBuffer!,
      maxStreams,
      waitTime,
    );
    if (streamCount < 0) {
      throw LSLException('Error resolving streams: $streamCount');
    }

    final streams = <LSLStreamInfo>[];
    for (var i = 0; i < streamCount; i++) {
      final streamInfo = LSLStreamInfo.fromStreamInfo(_streamInfoBuffer![i]);
      streams.add(streamInfo);
    }
    return streams;
  }

  @override

  /// Destroys the resolver and frees the stream info buffer.
  /// If the resolver is already destroyed, this method does nothing.
  void destroy() {
    if (destroyed) {
      return;
    }
    if (_streamInfoBuffer != null) {
      _streamInfoBuffer!.free();
      _streamInfoBuffer = null;
    }
    super.destroy();
  }
}

/// A filtered stream resolver that resolves streams by properties.
/// It is a subclass of [LSLStreamResolver] and allows you to filter streams
/// by properties such as stream name, type, etc.
extension LSLStreamResolverByProp on LSLStreamResolver {
  /// Resolves streams by a specific property.
  /// The [property] parameter is the property to filter by, such as name,
  /// type, channel count, etc.
  /// The [value] parameter is the value to filter by.
  /// The [waitTime] parameter determines how long to wait for streams to
  /// resolve, if the value is 0, the default of forever will be used, and will
  /// only return when the [minStreamCount] is met.
  /// The [minStreamCount] parameter is the minimum number of streams to
  /// resolve, it must be greater than 0.
  /// Returns a list of [LSLStreamInfo] objects that match the filter.
  /// Throws an [LSLException] if the resolver is not created or if there is an
  /// error resolving streams.
  /// You may get less streams than the [minStreamCount] if there are not enough
  /// streams available AND you have set a [waitTime] > 0.
  Future<List<LSLStreamInfo>> resolveByProperty({
    required LSLStreamProperty property,
    required String value,
    double waitTime = 5.0,
    int minStreamCount = 0,
  }) async {
    if (!created) {
      throw LSLException('Resolver not created');
    }

    final streamCount = lsl_resolve_byprop(
      _streamInfoBuffer!,
      maxStreams,
      property.lslName.toNativeUtf8(allocator: allocate).cast<Char>(),
      value.toNativeUtf8(allocator: allocate).cast<Char>(),
      minStreamCount,
      waitTime,
    );
    if (streamCount < 0) {
      throw LSLException('Error resolving streams by property: $streamCount');
    }

    final streams = <LSLStreamInfo>[];
    for (var i = 0; i < streamCount; i++) {
      final streamInfo = LSLStreamInfo.fromStreamInfo(_streamInfoBuffer![i]);
      streams.add(streamInfo);
    }
    return streams;
  }
}

/// A filtered stream resolver that resolves streams by a predicate expression.
extension LSLStreamResolverByPredicate on LSLStreamResolver {
  /// Resolves streams by a predicate function.
  /// The [predicate] parameter is an
  /// [XPath 1.0 predicate](http://en.wikipedia.org/w/index.php?title=XPath_1.0)
  /// e.g. `name='MyStream' and type='EEG'` or `starts-with(name, 'My')`.
  /// The [waitTime] parameter determines how long to wait for streams to
  /// resolve, if the value is 0, the default of forever will be used, and will
  /// only return when the [minStreamCount] is met.
  /// The [minStreamCount] parameter is the minimum number of streams to
  /// resolve, it must be greater than 0.
  Future<List<LSLStreamInfo>> resolveByPredicate({
    required String predicate,
    double waitTime = 5.0,
    int minStreamCount = 0,
  }) async {
    if (!created) {
      throw LSLException('Resolver not created');
    }

    final streamCount = lsl_resolve_bypred(
      _streamInfoBuffer!,
      maxStreams,
      predicate.toNativeUtf8(allocator: allocate).cast<Char>(),
      minStreamCount,
      waitTime,
    );
    if (streamCount < 0) {
      throw LSLException('Error resolving streams by predicate: $streamCount');
    }

    final streams = <LSLStreamInfo>[];
    for (var i = 0; i < streamCount; i++) {
      final streamInfo = LSLStreamInfo.fromStreamInfo(_streamInfoBuffer![i]);
      streams.add(streamInfo);
    }
    return streams;
  }
}

/// Representation of the lsl_continuous_resolver_ from the LSL C API.
///
/// Stream resolution means finding streams available on the network for
/// consumption.
class LSLStreamResolverContinuous extends LSLStreamResolver {
  final double forgetAfter;
  lsl_continuous_resolver? _resolver;

  /// Creates a new LSLStreamResolverContinuous object.
  ///
  /// The [forgetAfter] parameter determines how long the resolver should
  /// remember streams after they have not been seen.
  /// The [maxStreams] parameter determines the maximum number of streams
  /// to resolve, ideally, this would be the exact number of streams you expect
  /// to be available.
  LSLStreamResolverContinuous({this.forgetAfter = 5.0, super.maxStreams = 5});

  @override

  /// Creates the resolver and allocates the stream info buffer.
  /// This method initializes the resolver with the specified [forgetAfter]
  /// time, which is the duration after which streams that are not seen will be
  /// forgotten.
  /// Returns the created resolver instance.
  LSLStreamResolverContinuous create() {
    super.create();

    _resolver = lsl_create_continuous_resolver(forgetAfter);
    return this;
  }

  /// Resolves streams available on the network found since the last call to
  /// [resolve]. It will return all streams that are currently available,
  /// limited by [maxStreams].
  /// It is your responsibility to ensure that the returned streams are
  /// destroyed when no longer needed.
  @override
  Future<List<LSLStreamInfo>> resolve({double waitTime = 0.0}) async {
    if (_resolver == null) {
      throw LSLException('Resolver not created');
    }
    // pause for specified wait time
    // this is to allow the resolver to gather streams
    if (waitTime > 0) {
      await Future.delayed(Duration(milliseconds: (waitTime * 1000).toInt()));
    }

    final int streamCount = lsl_resolver_results(
      _resolver!,
      _streamInfoBuffer!,
      maxStreams,
    );
    if (streamCount < 0) {
      throw LSLException('Error resolving streams: $streamCount');
    }
    final streams = <LSLStreamInfo>[];
    for (var i = 0; i < streamCount; i++) {
      final streamInfo = LSLStreamInfo.fromStreamInfo(_streamInfoBuffer![i]);
      streams.add(streamInfo);
    }

    return streams;
  }

  @override
  void destroy() {
    if (destroyed) {
      return;
    }

    if (_resolver != null) {
      lsl_destroy_continuous_resolver(_resolver!);
      _resolver = null;
    }
    super.destroy();
  }

  @override
  String toString() {
    return 'LSLStreamResolverContinuous{maxStreams: $maxStreams, forgetAfter: $forgetAfter}';
  }
}

class LSLStreamResolverContinuousByPredicate
    extends LSLStreamResolverContinuous {
  final String predicate;

  /// Creates a new LSLStreamResolverContinuousByPredicate object.
  ///
  /// The [predicate] parameter is an
  /// [XPath 1.0 predicate](http://en.wikipedia.org/w/index.php?title=XPath_1.0)
  /// e.g. `name='MyStream' and type='EEG'` or `starts-with(name, 'My')`.
  /// The [forgetAfter] parameter determines how long the resolver should
  /// remember streams after they have not been seen.
  /// The [maxStreams] parameter determines the maximum number of streams
  /// to resolve, ideally, this would be the exact number of streams you expect
  /// to be available.
  LSLStreamResolverContinuousByPredicate({
    required this.predicate,
    super.forgetAfter = 5.0,
    super.maxStreams = 5,
  }) : super();

  @override
  LSLStreamResolverContinuous create() {
    super.create();

    _resolver = lsl_create_continuous_resolver_bypred(
      predicate.toNativeUtf8().cast<Char>(),
      forgetAfter,
    );
    return this;
  }

  @override
  String toString() {
    return 'LSLStreamResolverContinuousByPredicate{predicate: $predicate, maxStreams: $maxStreams, forgetAfter: $forgetAfter}';
  }

  @override
  // ignore: unnecessary_overrides
  void destroy() {
    super.destroy();
  }
}

class LSLStreamResolverContinuousByProperty
    extends LSLStreamResolverContinuous {
  final LSLStreamProperty property;
  final String value;

  /// Creates a new LSLStreamResolverContinuousByProperty object.
  ///
  /// The [property] parameter is the property to filter by, such as name,
  /// type, channel count, etc.
  /// The [value] parameter is the value to filter by.
  /// The [forgetAfter] parameter determines how long the resolver should
  /// remember streams after they have not been seen.
  /// The [maxStreams] parameter determines the maximum number of streams
  /// to resolve, ideally, this would be the exact number of streams you expect
  /// to be available.
  LSLStreamResolverContinuousByProperty({
    required this.property,
    required this.value,
    super.forgetAfter = 5.0,
    super.maxStreams = 5,
  }) : super();

  @override
  LSLStreamResolverContinuous create() {
    super.create();

    _resolver = lsl_create_continuous_resolver_byprop(
      property.lslName.toNativeUtf8().cast<Char>(),
      value.toNativeUtf8().cast<Char>(),
      forgetAfter,
    );
    return this;
  }

  @override
  String toString() {
    return 'LSLStreamResolverContinuousByProperty{property: $property, value: $value, maxStreams: $maxStreams, forgetAfter: $forgetAfter}';
  }

  @override
  // ignore: unnecessary_overrides
  void destroy() {
    super.destroy();
  }
}
