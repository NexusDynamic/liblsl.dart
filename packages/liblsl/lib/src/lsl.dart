import 'dart:async';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/api_config.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/inlet.dart';
import 'package:liblsl/src/lsl/outlet.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/stream_resolver.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer, StringUtf8Pointer;

// Export LSL constants for public use
export 'package:liblsl/native_liblsl.dart' show LSL_FOREVER, LSL_IRREGULAR_RATE;

/// Interface to the LSL library.
///
/// This class provides a high-level interface to the LSL library, allowing
/// you to create and manage streams, outlets, and inlets.
class LSL {
  /// Don't use this constructor directly, use [LSL.createStreamInfo],
  /// [LSL.createOutlet], or [LSL.createInlet] instead.
  LSL._();

  /// Sets the configuration filename for the LSL library.
  ///
  /// @param [filename] The path to the configuration file.
  ///
  /// @note: This should be called before any other LSL operations.
  /// @note: see https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#configuration-file-contents
  static void setConfigFilename(String filename) {
    final filenamePtr = filename.toNativeUtf8();
    lsl_set_config_filename(filenamePtr.cast());
    filenamePtr.free();
  }

  /// Sets the configuration for the LSL library.
  ///
  /// @param [content] The configuration [LSLApiConfig].
  ///
  /// @note: This should be called before any other LSL operations.
  /// @note: see https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#configuration-file-contents
  static void setConfigContent(LSLApiConfig content) {
    final contentPtr = content.toIniString().toNativeUtf8();
    lsl_set_config_content(contentPtr.cast());
    contentPtr.free();
  }

  /// Creates a new [LSLStreamInfo] object.
  ///
  /// [streamName] is the name of the stream.
  /// [streamType] is the [LSLContentType] of the stream (e.g. EEG, mocap, ...).
  /// [channelCount] is the number of channels in the stream.
  /// [streamType] is the stream's [LSLChannelFormat] (e.g. string, int8).
  /// [sourceId] is the source ID of the stream which should be unique.
  static Future<LSLStreamInfoWithMetadata> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 1,
    double sampleRate = 150.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) async {
    final streamInfo = LSLStreamInfoWithMetadata(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
      streamInfo: null, // Will be created in create() method
    );
    streamInfo.create();
    return streamInfo;
  }

  /// Returns the version of the LSL library.
  static int get version => lsl_library_version();

  /// Creates a new outlet object.
  ///
  /// [chunkSize] determines how to hand off samples to the buffer,
  /// 0 creates a chunk for each push.
  ///
  /// [maxBuffer] determines the size of the buffer that stores incoming
  /// samples. NOTE: This is in seconds, if the stream has a sample rate,
  /// otherwise it is in 100s of samples (maxBuffer * 10^2).
  /// High values will use more memory, low values may lose samples,
  /// this should be set as close as possible to the rate of consumption.
  /// [useIsolates] determines whether to use isolates for thread safety.
  /// If true, the outlet will use isolates to ensure thread safety.
  /// Important: If you do not use isolates, you must ensure that you deal with
  /// the consequences of blocking operations which will block the main dart
  /// isolate.
  static Future<LSLOutlet> createOutlet({
    required LSLStreamInfo streamInfo,
    int chunkSize = 1,
    int maxBuffer = 360,
    bool useIsolates = true,
  }) async {
    final streamOutlet = LSLOutlet(
      streamInfo,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
      useIsolates: useIsolates,
    );
    await streamOutlet.create();

    return streamOutlet;
  }

  /// Creates a new inlet object.
  ///
  /// [streamInfo] is the [LSLStreamInfo] object to be used. Probably obtained
  ///   from a [LSLStreamResolver].
  /// [maxBuffer] this is the either seconds (if [streamInfo].sampleRate
  /// is specified) or 100s of samples (if not).
  /// [chunkSize] is the maximum number of samples. If 0, the default
  ///  chunk length from the stream is used.
  /// [recover] is whether to recover from lost samples.
  /// [createTimeout] is the timeout for creating the inlet.
  /// [includeMetadata] if true, the stream info will include metadata access.
  /// This will automatically fetch full stream info with metadata.
  /// [useIsolates] determines whether to use isolates for thread safety.
  /// If true, the inlet will use isolates to ensure thread safety.
  /// Important: If you do not use isolates, you must ensure that you deal with
  /// the consequences of blocking operations which will block the main dart
  /// isolate.
  static Future<LSLInlet<T>> createInlet<T>({
    required LSLStreamInfo streamInfo,
    int maxBuffer = 360,
    int chunkSize = 0,
    bool recover = true,
    double createTimeout = LSL_FOREVER,
    bool includeMetadata = false,
    bool useIsolates = true,
  }) async {
    if (!streamInfo.created) {
      throw LSLException('StreamInfo not created');
    }

    Type dataType;
    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        dataType = double;
        break;
      case const (int):
        dataType = int;
        break;
      case const (String):
        dataType = String;
        break;
      default:
        throw LSLException('Invalid channel format');
    }

    // Check if the generic type matches the expected data type
    if (T != dynamic && T != dataType) {
      throw LSLException(
        'Generic type $T does not match expected data type $dataType for channel format ${streamInfo.channelFormat}',
      );
    }

    // Create inlet and get full info if metadata is requested
    LSLInlet inlet;
    if (dataType == double) {
      inlet = LSLInlet<double>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
    } else if (dataType == int) {
      inlet = LSLInlet<int>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
    } else if (dataType == String) {
      inlet = LSLInlet<String>(
        streamInfo,
        maxBuffer: maxBuffer,
        chunkSize: chunkSize,
        recover: recover,
        createTimeout: createTimeout,
        useIsolates: useIsolates,
      );
    } else {
      throw LSLException('Unsupported data type: $dataType');
    }

    await inlet.create();

    // If metadata is requested and we don't already have it, get full info from the inlet
    if (includeMetadata && streamInfo is! LSLStreamInfoWithMetadata) {
      await inlet.getFullInfo(timeout: createTimeout);
    }

    return inlet as LSLInlet<T>;
  }

  /// Discovers all available LSL streams on the network.
  ///
  /// This method provides a simple way to find all streams currently broadcasting
  /// on the network without any filtering criteria. It's ideal for discovery
  /// scenarios where you want to see what's available.
  ///
  /// **Parameters:**
  /// - [waitTime]: Maximum time to wait for streams (default: 5.0 seconds)
  /// - [maxStreams]: Maximum number of streams to return (default: 5)
  ///
  /// **Returns:** List of [LSLStreamInfo] objects representing discovered streams
  ///
  /// **Usage Example:**
  /// ```dart
  /// // Discover all available streams
  /// final streams = await LSL.resolveStreams(waitTime: 2.0);
  /// for (final stream in streams) {
  ///   print('Found: ${stream.streamName} (${stream.streamType})');
  /// }
  /// ```
  ///
  /// **Performance Note:**
  /// This method creates and destroys a resolver for each call. For continuous
  /// monitoring, use [createContinuousStreamResolver] for better efficiency.
  ///
  /// **See Also:**
  /// - [resolveStreamsByProperty] for property-based filtering
  /// - [resolveStreamsByPredicate] for complex XPath filtering
  /// - [createContinuousStreamResolver] for continuous monitoring
  static Future<List<LSLStreamInfo>> resolveStreams({
    double waitTime = 5.0,
    int maxStreams = 5,
  }) async {
    final resolver = createResolver(maxStreams: maxStreams);
    final streams = await resolver.resolve(waitTime: waitTime);
    // free the resolver
    resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  /// Discovers LSL streams matching a specific property value.
  ///
  /// This method filters streams based on a single property-value pair,
  /// making it ideal for finding streams by name, type, or other specific
  /// characteristics.
  ///
  /// **Parameters:**
  /// - [property]: The stream property to filter by (see [LSLStreamProperty])
  /// - [value]: The exact value to match (case-sensitive)
  /// - [waitTime]: Maximum wait time in seconds (default: 5.0)
  /// - [minStreamCount]: Minimum streams to find before returning (default: 0)
  /// - [maxStreams]: Maximum streams to return (default: 5)
  ///
  /// **Available Properties:**
  /// - `name`: Stream name (exact match)
  /// - `type`: Content type (e.g., 'EEG', 'EMG', 'Audio')
  /// - `channelCount`: Number of channels (as string)
  /// - `sampleRate`: Sampling rate (as string with full precision)
  /// - `channelFormat`: Data format (e.g., 'float32', 'int16')
  /// - `sourceId`: Unique source identifier
  ///
  /// **Usage Examples:**
  /// ```dart
  /// // Find EEG streams
  /// final eegStreams = await LSL.resolveStreamsByProperty(
  ///   property: LSLStreamProperty.type,
  ///   value: 'EEG',
  ///   waitTime: 2.0,
  /// );
  ///
  /// // Find a specific stream by name
  /// final myStream = await LSL.resolveStreamsByProperty(
  ///   property: LSLStreamProperty.name,
  ///   value: 'MyDataStream',
  ///   waitTime: 1.0,
  /// );
  /// ```
  ///
  /// **Returns:** List of [LSLStreamInfo] objects matching the criteria
  ///
  /// **Note:** If [minStreamCount] > 0 and [waitTime] > 0, the method may
  /// return fewer streams than requested if the timeout is reached.
  ///
  /// **See Also:**
  /// - [resolveStreamsByPredicate] for complex filtering with XPath
  /// - [resolveStreams] for discovering all streams
  static Future<List<LSLStreamInfo>> resolveStreamsByProperty({
    required LSLStreamProperty property,
    required String value,
    double waitTime = 5.0,
    int minStreamCount = 0,
    int maxStreams = 5,
  }) async {
    final resolver = createResolver(maxStreams: maxStreams);
    final streams = await resolver.resolveByProperty(
      property: property,
      value: value,
      waitTime: waitTime,
      minStreamCount: minStreamCount,
    );
    // free the resolver
    resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  /// Discovers LSL streams using XPath 1.0 predicate expressions.
  ///
  /// This method provides powerful filtering capabilities using XPath predicates,
  /// allowing complex queries involving multiple criteria, text functions,
  /// and metadata inspection.
  ///
  /// **Parameters:**
  /// - [predicate]: XPath 1.0 predicate expression (see examples below)
  /// - [waitTime]: Maximum wait time in seconds (default: 5.0)
  /// - [minStreamCount]: Minimum streams to find before returning (default: 0)
  /// - [maxStreams]: Maximum streams to return (default: 5)
  ///
  /// **Available XPath Functions:**
  /// - `starts-with(field, text)`: Check if field starts with text
  /// - `contains(field, text)`: Check if field contains text
  /// - `count(path)`: Count matching elements in metadata
  /// - Standard comparison operators: `=`, `!=`, `<`, `<=`, `>`, `>=`
  /// - Logical operators: `and`, `or`, `not()`
  ///
  /// **Queryable Fields:**
  /// - `name`: Stream name
  /// - `type`: Content type
  /// - `channel_count`: Number of channels
  /// - `nominal_srate`: Sample rate
  /// - `source_id`: Source identifier
  /// - `//info/desc/...`: Metadata elements in description
  ///
  /// **Usage Examples:**
  /// ```dart
  /// // Basic property matching
  /// final streams = await LSL.resolveStreamsByPredicate(
  ///   predicate: "name='EEG_Stream' and type='EEG'",
  /// );
  ///
  /// // Text functions
  /// final bioStreams = await LSL.resolveStreamsByPredicate(
  ///   predicate: "starts-with(name, 'BioSemi') or contains(name, 'EEG')",
  /// );
  ///
  /// // Numeric comparisons
  /// final highSampleRate = await LSL.resolveStreamsByPredicate(
  ///   predicate: "nominal_srate >= 1000 and channel_count = 32",
  /// );
  ///
  /// // Metadata queries
  /// final withChannels = await LSL.resolveStreamsByPredicate(
  ///   predicate: "count(//info/desc/channels/channel) > 0",
  /// );
  /// ```
  ///
  /// **Returns:** List of [LSLStreamInfo] objects matching the predicate
  ///
  /// **Error Handling:**
  /// Invalid XPath expressions return empty results rather than throwing exceptions.
  ///
  /// **See Also:**
  /// - [XPath 1.0 Specification](http://en.wikipedia.org/w/index.php?title=XPath_1.0)
  /// - [resolveStreamsByProperty] for simple property filtering
  /// - [resolveStreams] for discovering all streams
  static Future<List<LSLStreamInfo>> resolveStreamsByPredicate({
    required String predicate,
    double waitTime = 5.0,
    int minStreamCount = 0,
    int maxStreams = 5,
  }) async {
    final resolver = createResolver(maxStreams: maxStreams);
    final streams = await resolver.resolveByPredicate(
      predicate: predicate,
      waitTime: waitTime,
      minStreamCount: minStreamCount,
    );
    // free the resolver
    resolver.destroy();
    // these stream info pointers remain until they are destroyed
    return streams;
  }

  static LSLStreamResolver createResolver({int maxStreams = 5}) {
    return LSLStreamResolver(maxStreams: maxStreams)..create();
  }

  /// Creates a continuous stream resolver for efficient long-term monitoring.
  ///
  /// Unlike one-shot resolution methods, this creates a persistent resolver that
  /// continuously monitors for streams in the background, providing efficient
  /// repeated queries without the overhead of creating new resolvers.
  ///
  /// **Parameters:**
  /// - [forgetAfter]: Time in seconds to forget unseen streams (default: 5.0)
  /// - [maxStreams]: Maximum number of streams to track (default: 5)
  ///
  /// **Key Features:**
  /// - Continuous background monitoring
  /// - Automatic stream discovery and forgetting
  /// - Support for property and predicate filtering
  /// - Memory efficient for repeated queries
  ///
  /// **Usage Example:**
  /// ```dart
  /// // Create continuous resolver
  /// final resolver = LSL.createContinuousStreamResolver(
  ///   forgetAfter: 10.0,
  ///   maxStreams: 20,
  /// );
  ///
  /// // Use for multiple queries
  /// final allStreams = await resolver.resolve(waitTime: 1.0);
  /// // later
  /// final moreStreams = await resolver.resolve(waitTime: 5.0);
  ///
  /// // Clean up when done
  /// resolver.destroy();
  /// ```
  ///
  /// **Memory Management:**
  /// Always call [LSLStreamResolverContinuous.destroy] when finished to
  /// prevent memory leaks. The resolver runs background threads that need
  /// explicit cleanup.
  ///
  /// **Performance:**
  /// Ideal for applications that need frequent stream discovery, such as
  /// real-time monitoring dashboards or connection managers.
  ///
  /// **Returns:** Configured and initialized [LSLStreamResolverContinuous]
  ///
  /// **See Also:**
  /// - [LSLStreamResolverContinuous.resolve] for basic resolution
  /// - [LSLStreamResolverContinuous.resolveByProperty] for property filtering
  /// - [LSLStreamResolverContinuous.resolveByPredicate] for XPath filtering
  static LSLStreamResolverContinuous createContinuousStreamResolver({
    double forgetAfter = 5.0,
    int maxStreams = 5,
  }) {
    return LSLStreamResolverContinuous(
      forgetAfter: forgetAfter,
      maxStreams: maxStreams,
    )..create();
  }

  /// Returns the local clock time, used to calculate offsets.
  static double localClock() => lsl_local_clock();

  /// Returns the version of the LSL library.
  static String libraryInfo() {
    final version = lsl_library_info();
    if (version.isNullPointer) {
      throw LSLException('Failed to get library info');
    }
    final versionString = version.cast<Utf8>().toDartString();
    return versionString;
  }

  /// Cleans up all resources.
  void destroy() {}

  @override
  String toString() {
    return 'LSL{version: $version}';
  }
}
