import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, Utf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Runs [fn] with a temporary native UTF-8 copy of [value], freed after.
T _withUtf8<T>(String value, T Function(Pointer<Char> ptr) fn) {
  final ptr = value.toNativeUtf8(allocator: allocate);
  try {
    return fn(ptr.cast<Char>());
  } finally {
    ptr.free();
  }
}

extension StreamInfoList on List<LSLStreamInfo> {
  void destroy() {
    for (final streamInfo in this) {
      streamInfo.destroy();
    }
  }
}

/// Base class for interacting with LibLSL XML elements.
///
/// This class provides low-level access to LibLSL's XML API, allowing navigation
/// and inspection of XML nodes. Most users should use [LSLXmlNode] instead for
/// a higher-level interface.
///
/// The XML structure in LibLSL follows standard XML conventions with elements
/// that can contain text content and/or child elements.
class LSLXml {
  /// The underlying LibLSL XML pointer.
  final lsl_xml_ptr xmlPtr;

  /// Creates a new LSLXml object.
  LSLXml({required this.xmlPtr}) {
    if (xmlPtr.isNullPointer) {
      throw LSLException('Invalid XML pointer');
    }
  }

  String _lslName() {
    final namePtr = lsl_name(xmlPtr);
    if (namePtr.isNullPointer) {
      throw LSLException('Failed to get XML name');
    }
    return namePtr.cast<Utf8>().toDartString();
  }

  String _lslValue() {
    // Try lsl_child_value first, as lsl_append_child_value creates a text child
    final childValuePtr = lsl_child_value(xmlPtr);
    if (!childValuePtr.isNullPointer) {
      return childValuePtr.cast<Utf8>().toDartString();
    }

    // Fall back to lsl_value
    final valuePtr = lsl_value(xmlPtr);
    if (valuePtr.isNullPointer) {
      throw LSLException('Failed to get XML value');
    }
    return valuePtr.cast<Utf8>().toDartString();
  }

  LSLXmlNode? parent() {
    final parentPtr = lsl_parent(xmlPtr);
    if (parentPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(parentPtr);
  }

  bool isText() {
    return lsl_is_text(xmlPtr) != 0;
  }

  bool isEmpty() {
    return lsl_empty(xmlPtr) != 0;
  }

  LSLXmlNode? nextSibling() {
    final nextPtr = lsl_next_sibling(xmlPtr);
    if (nextPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(nextPtr);
  }

  LSLXmlNode? nextSiblingNamed(String name) {
    final nextPtr = lsl_next_sibling_n(
      xmlPtr,
      name.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (nextPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(nextPtr);
  }

  LSLXmlNode? previousSibling() {
    final prevPtr = lsl_previous_sibling(xmlPtr);
    if (prevPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(prevPtr);
  }

  LSLXmlNode? previousSiblingNamed(String name) {
    final prevPtr = lsl_previous_sibling_n(
      xmlPtr,
      name.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (prevPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(prevPtr);
  }

  LSLXmlNode? firstChild() {
    final firstChildPtr = lsl_first_child(xmlPtr);
    if (firstChildPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(firstChildPtr);
  }

  LSLXmlNode? childNamed(String name) {
    final childPtr = lsl_child(
      xmlPtr,
      name.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (childPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(childPtr);
  }

  LSLXmlNode? lastChild() {
    final lastChildPtr = lsl_last_child(xmlPtr);
    if (lastChildPtr.isNullPointer) {
      return null;
    }
    return LSLXmlNode.fromXmlPtr(lastChildPtr);
  }
}

/// An XML node in LibLSL's metadata structure.
///
/// This class represents a unified XML node that can contain both text content
/// and child elements, matching LibLSL's C API behavior. Unlike separate element
/// and text node classes, this unified approach handles both `<name>value</name>`
/// and `<name><child/></name>` patterns seamlessly.
///
/// **Key Features:**
/// - Access text content via [textValue] getter/setter
/// - Access child elements via [children] getter
/// - Add child elements with [addChildElement] and [addChildValue]
/// - Navigate hierarchy with inherited methods from [LSLXml]
///
/// **Example Usage:**
/// ```dart
/// final root = description.value;
///
/// // Add text content: <manufacturer>SCCN</manufacturer>
/// root.addChildValue('manufacturer', 'SCCN');
///
/// // Add container element: <channels></channels>
/// final channels = root.addChildElement('channels');
///
/// // Add nested structure
/// final channel = channels.addChildElement('channel');
/// channel.addChildValue('label', 'C3');
/// ```
class LSLXmlNode extends LSLXml {
  String get name => _name;
  set name(String value) {
    if (value.isEmpty) {
      throw LSLException('Node name cannot be empty');
    }
    final int result = lsl_set_name(
      xmlPtr,
      value.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (result == 0) {
      throw LSLException('Failed to set node name: $value');
    }
    _name = value;
  }

  String _name;

  /// Gets the text value of this element (if it has text content)
  String get textValue => _lslValue();

  /// Sets the text value of this element
  set textValue(String value) {
    if (value.isEmpty) {
      throw LSLException('Text value cannot be empty');
    }
    final int result = lsl_set_value(
      xmlPtr,
      value.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (result == 0) {
      throw LSLException('Failed to set text value: $value');
    }
  }

  /// Gets child elements of this element
  List<LSLXmlNode> get children => _getChildren();

  LSLXmlNode._internal(this._name, {required super.xmlPtr});

  factory LSLXmlNode.fromXmlPtr(lsl_xml_ptr xmlPtr) {
    final xml = LSLXml(xmlPtr: xmlPtr);
    return LSLXmlNode._internal(xml._lslName(), xmlPtr: xmlPtr);
  }

  List<LSLXmlNode> _getChildren() {
    final children = <LSLXmlNode>[];
    final firstChildXml = firstChild();

    if (firstChildXml == null || firstChildXml.isEmpty()) {
      return children;
    }

    final lastChildXml = lastChild();
    LSLXmlNode? child = firstChildXml;
    while (child != null) {
      children.add(child);
      if (child.xmlPtr.address == lastChildXml?.xmlPtr.address) break;
      child = child.nextSibling();
    }

    return children;
  }

  /// Adds a child element with text content (like &lt;name&gt;value&lt;/name&gt;)
  LSLXmlNode addChildValue(String name, String value) {
    if (name.isEmpty) {
      throw LSLException('Child name cannot be empty');
    }
    lsl_append_child_value(
      xmlPtr,
      name.toNativeUtf8(allocator: allocate).cast<Char>(),
      value.toNativeUtf8(allocator: allocate).cast<Char>(),
    );

    // Get the last child, which should be the one we just added
    final lastChildPtr = lsl_last_child(xmlPtr);
    if (lastChildPtr.isNullPointer) {
      throw LSLException('Failed to add child value: $name');
    }

    return LSLXmlNode.fromXmlPtr(lastChildPtr);
  }

  /// Adds a child element (like &lt;name&gt;&lt;/name&gt;)
  LSLXmlNode addChildElement(String name) {
    if (name.isEmpty) {
      throw LSLException('Child name cannot be empty');
    }
    final childPtr = lsl_append_child(
      xmlPtr,
      name.toNativeUtf8(allocator: allocate).cast<Char>(),
    );
    if (childPtr.isNullPointer) {
      throw LSLException('Failed to add child element: $name');
    }
    return LSLXmlNode.fromXmlPtr(childPtr);
  }

  /// Inserts a child element with text content as the *first* child
  /// (like [addChildValue], which appends).
  LSLXmlNode prependChildValue(String name, String value) {
    if (name.isEmpty) {
      throw LSLException('Child name cannot be empty');
    }
    // lsl_prepend_child_value returns the parent, not the new child.
    _withUtf8(
      name,
      (n) => _withUtf8(value, (v) => lsl_prepend_child_value(xmlPtr, n, v)),
    );
    final firstChildPtr = lsl_first_child(xmlPtr);
    if (firstChildPtr.isNullPointer) {
      throw LSLException('Failed to prepend child value: $name');
    }
    return LSLXmlNode.fromXmlPtr(firstChildPtr);
  }

  /// Inserts an empty child element as the *first* child (like
  /// [addChildElement], which appends).
  LSLXmlNode prependChildElement(String name) {
    if (name.isEmpty) {
      throw LSLException('Child name cannot be empty');
    }
    final childPtr = _withUtf8(name, (n) => lsl_prepend_child(xmlPtr, n));
    if (childPtr.isNullPointer) {
      throw LSLException('Failed to prepend child element: $name');
    }
    return LSLXmlNode.fromXmlPtr(childPtr);
  }

  /// Appends a deep copy of [node] (which may live in another stream info's
  /// description) as the last child; returns the copy.
  LSLXmlNode appendCopy(LSLXml node) {
    final copyPtr = lsl_append_copy(xmlPtr, node.xmlPtr);
    if (copyPtr.isNullPointer) {
      throw LSLException('Failed to append copy of node');
    }
    return LSLXmlNode.fromXmlPtr(copyPtr);
  }

  /// Inserts a deep copy of [node] as the first child; returns the copy.
  LSLXmlNode prependCopy(LSLXml node) {
    final copyPtr = lsl_prepend_copy(xmlPtr, node.xmlPtr);
    if (copyPtr.isNullPointer) {
      throw LSLException('Failed to prepend copy of node');
    }
    return LSLXmlNode.fromXmlPtr(copyPtr);
  }

  /// Text content of the first child element named [name] (empty if there
  /// is no such child or it has no text).
  String childValueNamed(String name) {
    final valuePtr = _withUtf8(name, (n) => lsl_child_value_n(xmlPtr, n));
    if (valuePtr.isNullPointer) {
      return '';
    }
    return valuePtr.cast<Utf8>().toDartString();
  }

  /// Replaces the text content of the first child element named [name].
  ///
  /// Only works for a child that already has text content (e.g. one made
  /// with [addChildValue]); returns `false` otherwise, or if there is no
  /// such child.
  bool setChildValue(String name, String value) =>
      _withUtf8(
        name,
        (n) => _withUtf8(value, (v) => lsl_set_child_value(xmlPtr, n, v)),
      ) !=
      0;

  /// Removes [child] (a direct child of this node) and its subtree.
  ///
  /// [child] and any other [LSLXmlNode] referring into its subtree become
  /// invalid.
  void removeChild(LSLXml child) {
    lsl_remove_child(xmlPtr, child.xmlPtr);
  }

  /// Removes the first child element named [name] (no-op if none).
  ///
  /// Any [LSLXmlNode] referring into the removed subtree becomes invalid.
  void removeChildNamed(String name) {
    _withUtf8(name, (n) => lsl_remove_child_n(xmlPtr, n));
  }

  @override
  String toString() =>
      'LSLXmlNode[$name]: ${textValue.isEmpty ? '${children.length} children' : textValue}';

  /// check equality based on pointer address
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLXmlNode) return false;
    return xmlPtr.address == other.xmlPtr.address;
  }

  @override
  int get hashCode => xmlPtr.address.hashCode;
}

/// Provides access to a stream's metadata description element.
///
/// This class wraps LibLSL's description XML structure, providing a Dart-friendly
/// interface for accessing and modifying stream metadata. The description contains
/// the root XML element that can hold manufacturer info, channel details,
/// acquisition settings, and other custom metadata.
///
/// **Key Properties:**
/// - [value]: The root XML node of the description
///
/// **Usage Pattern:**
/// ```dart
/// final streamInfo = await LSL.createStreamInfo(...);
/// final description = streamInfo.description;
/// final rootElement = description.value;
///
/// // Add metadata
/// rootElement.addChildValue('manufacturer', 'SCCN');
/// final channels = rootElement.addChildElement('channels');
/// ```
///
/// **Memory Management:**
/// The description shares the lifetime of its parent [LSLStreamInfoWithMetadata].
/// Destroying the stream info will invalidate this description.
class LSLDescription {
  final lsl_streaminfo _fullInfo;
  late final lsl_xml_ptr _descriptionPtr;
  late final LSLXmlNode value;

  LSLDescription(this._fullInfo) {
    _descriptionPtr = lsl_get_desc(_fullInfo);
    if (_descriptionPtr.isNullPointer) {
      throw LSLException('Failed to get description pointer');
    }
    value = LSLXmlNode.fromXmlPtr(_descriptionPtr);
  }
}

/// Representation of the lsl_streaminfo_struct_ from the LSL C API.
class LSLStreamInfo extends LSLObj {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;
  lsl_streaminfo? _streamInfo;

  /// Creates a new LSLStreamInfo object.
  ///
  /// The [streamName], [streamType], [channelCount], [sampleRate],
  /// [channelFormat], and [sourceId] parameters are used to create
  /// the stream info object.
  LSLStreamInfo({
    this.streamName = "DartLSLStream",
    this.streamType = LSLContentType.eeg,
    this.channelCount = 16,
    this.sampleRate = 250.0,
    this.channelFormat = LSLChannelFormat.float32,
    this.sourceId = "DartLSL",
    lsl_streaminfo? streamInfo,
  }) : _streamInfo = streamInfo {
    if (_streamInfo != null) {
      super.create();
    }
  }

  /// The [Pointer] to the underlying lsl_streaminfo_struct_.
  lsl_streaminfo get streamInfo =>
      _streamInfo ??
      (throw LSLException('StreamInfo not created or destroyed'));

  /// Creates the stream info object, allocates memory, etc.
  @override
  LSLStreamInfo create() {
    if (created) {
      throw LSLException('StreamInfo already created');
    }
    final streamNamePtr = streamName
        .toNativeUtf8(allocator: allocate)
        .cast<Char>();
    final sourceIdPtr = sourceId.toNativeUtf8(allocator: allocate).cast<Char>();
    final streamTypePtr = streamType.charPtr;

    addAllocList([streamNamePtr, sourceIdPtr, streamTypePtr]);
    _streamInfo = lsl_create_streaminfo(
      streamNamePtr,
      streamTypePtr,
      channelCount,
      sampleRate,
      channelFormat.lslFormat,
      sourceIdPtr,
    );
    // if the UID is not set, we create a new one
    if (uid == null) {
      resetUid();
    }
    super.create();
    return this;
  }

  String? get uid {
    if (_streamInfo == null) {
      return null;
    }
    final Pointer<Char> uidp = lsl_get_uid(_streamInfo!);
    if (uidp.isNullPointer) {
      return null;
    }

    try {
      final String uidValue = uidp.cast<Utf8>().toDartString();
      if (uidValue.isEmpty) {
        return null;
      }
      return uidValue;
    } catch (e) {
      return null;
    }
  }

  String? get hostname {
    if (_streamInfo == null) {
      return null;
    }

    final Pointer<Char> hostPtr = lsl_get_hostname(_streamInfo!);
    if (hostPtr.isNullPointer) {
      return null;
    }

    try {
      return hostPtr.cast<Utf8>().toDartString();
    } catch (e) {
      return null;
    }
  }

  lsl_streaminfo get _infoBang =>
      _streamInfo ??
      (throw LSLException('StreamInfo not created or destroyed'));

  /// Number of bytes occupied by one channel value (0 for string streams,
  /// whose values are variable-length).
  int get channelBytes => lsl_get_channel_bytes(_infoBang);

  /// Number of bytes occupied by one sample (`channelBytes * channelCount`;
  /// 0 for string streams).
  int get sampleBytes => lsl_get_sample_bytes(_infoBang);

  /// [LSL.localClock] time at which the stream was created on the sending
  /// machine (0.0 for a stream info that has not been served by an outlet).
  double get createdAt => lsl_get_created_at(_infoBang);

  /// The session ID the stream belongs to (`'default'` unless configured
  /// via [LSLApiConfig.sessionId]); resolvers only see streams sharing
  /// their own session ID.
  String get sessionId =>
      lsl_get_session_id(_infoBang).cast<Utf8>().toDartString();

  /// The LSL protocol version the stream info was created with (e.g. 110
  /// for 1.10).
  int get protocolVersion => lsl_get_version(_infoBang);

  /// Whether this stream info matches the XPath 1.0 [query] (the same
  /// predicate syntax as [LSL.resolveStreamsByPredicate], e.g.
  /// `"name='EEG' and type='EEG'"`).
  bool matchesQuery(String query) =>
      _withUtf8(query, (q) => lsl_stream_info_matches_query(_infoBang, q)) != 0;

  /// Creates an independent deep copy of this stream info (including its
  /// description). The copy owns its native handle: call [destroy] on it
  /// when done; it stays valid after this object is destroyed.
  LSLStreamInfoWithMetadata copy() {
    final copied = lsl_copy_streaminfo(_infoBang);
    if (copied.isNullPointer) {
      throw LSLException('Failed to copy stream info');
    }
    return LSLStreamInfoWithMetadata.fromStreamInfo(copied);
  }

  /// Creates a new LSLStreamInfo object from an existing stream info address.
  ////
  /// When constructing inlets, this creates the [LSLStreamInfo] object based
  /// on an existing stream info address, which can be retrieved from a
  /// stream resolver.
  factory LSLStreamInfo.fromStreamInfoAddr(int address) {
    /// @TODO: Validate memory management - what happens to THIS pointer?
    final streamInfo = lsl_streaminfo.fromAddress(address);
    if (streamInfo.isNullPointer) {
      throw LSLException('Invalid stream info address');
    }
    return LSLStreamInfo.fromStreamInfo(streamInfo);
  }

  /// Creates a new LSLStreamInfo object from an existing lsl_streaminfo.
  ///
  /// When constructing inlets, this creates the [LSLStreamInfo] object based
  /// on an existing [lsl_streaminfo] object, which can be retrieved from a
  /// stream resolver.
  factory LSLStreamInfo.fromStreamInfo(lsl_streaminfo streamInfo) {
    final Pointer<Utf8> streamName = lsl_get_name(streamInfo) as Pointer<Utf8>;
    final Pointer<Utf8> streamType = lsl_get_type(streamInfo) as Pointer<Utf8>;
    final int channelCount = lsl_get_channel_count(streamInfo);
    final double sampleRate = lsl_get_nominal_srate(streamInfo);
    final lsl_channel_format_t channelFormat = lsl_get_channel_format(
      streamInfo,
    );
    final Pointer<Utf8> sourceId =
        lsl_get_source_id(streamInfo) as Pointer<Utf8>;
    final String streamTypeString = streamType.toDartString();
    final info = LSLStreamInfo(
      streamName: streamName.toDartString(),
      streamType: LSLContentType.values.firstWhere(
        (e) => e.value == streamTypeString,
        orElse: () => LSLContentType.custom(
          streamTypeString,
        ), // Default to custom if not found
      ),
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: LSLChannelFormat.values.firstWhere(
        (e) => e.lslFormat == channelFormat,
        orElse: () =>
            LSLChannelFormat.float32, // Default to float32 if not found
      ),
      sourceId: sourceId.toDartString(),
      streamInfo: streamInfo,
    );
    return info;
  }

  String toXml() {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created or destroyed');
    }
    final Pointer<Char> xmlPtr = lsl_get_xml(_streamInfo!);
    if (xmlPtr.isNullPointer) {
      throw LSLException('Failed to get XML representation of stream info');
    }
    return xmlPtr.cast<Utf8>().toDartString();
  }

  LSLStreamInfoWithMetadata fromXml(String xml) {
    final Pointer<Char> xmlPtr = xml
        .toNativeUtf8(allocator: allocate)
        .cast<Char>();
    final lsl_streaminfo streamInfo = lsl_streaminfo_from_xml(xmlPtr);
    if (streamInfo.isNullPointer) {
      throw LSLException('Failed to create stream info from XML');
    }
    // now we have to check the "name" field. If it starts with "(invalid: "
    // then there was an error, unfortunately LSL doesn't return a null pointer
    // on exception in the c++ code, so we have to check the name field
    final Pointer<Char> namePtr = lsl_get_name(streamInfo);
    if (namePtr.isNullPointer) {
      lsl_destroy_streaminfo(streamInfo);
      throw LSLException('Failed to create stream info from XML: $xml');
    }
    final String name = namePtr.cast<Utf8>().toDartString();
    if (name.startsWith('(invalid: ')) {
      lsl_destroy_streaminfo(streamInfo);
      throw LSLException(
        'Failed to create stream info from XML: $xml, error: $name',
      );
    }
    return LSLStreamInfoWithMetadata.fromStreamInfo(streamInfo);
  }

  /// Resets the stream info's UID.
  /// @note This is not a common operation and should be used with caution.
  /// This retuns the new UID as a string.
  String resetUid() {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created or destroyed');
    }
    final Pointer<Char> result = lsl_reset_uid(_streamInfo!);
    if (result.isNullPointer) {
      throw LSLException('Failed to reset UID');
    }
    final uid = result.cast<Utf8>().toDartString();
    return uid;
  }

  @override
  void destroy() {
    if (destroyed) {
      return;
    }
    if (_streamInfo != null) {
      lsl_destroy_streaminfo(_streamInfo!);
      //allocate.free(_streamInfo!);
      _streamInfo = null;
    }
    super.destroy();
  }

  // lsl_xml_ptr addMetadataGroup(String groupName) {
  //   if (_streamInfo == null) {
  //     throw LSLException('StreamInfo not created or destroyed');
  //   }
  //   final groupNamePtr = groupName
  //       .toNativeUtf8(allocator: allocate)
  //       .cast<Char>();
  //   addAllocList([groupNamePtr]);
  //   return lsl_add_metadata_group(_streamInfo!, groupNamePtr);
  // }

  @override
  String toString() {
    return 'LSLStreamInfo[$uid]{streamName: $streamName, streamType: $streamType, channelCount: $channelCount, sampleRate: $sampleRate, channelFormat: $channelFormat, sourceId: $sourceId, host: $hostname}';
  }

  @override
  int get hashCode => Object.hash(
    _streamInfo?.address,
    streamName,
    streamType,
    channelCount,
    sampleRate,
    channelFormat,
    sourceId,
    uid,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLStreamInfo) return false;
    return _streamInfo?.address == other._streamInfo?.address &&
        streamName == other.streamName &&
        streamType == other.streamType &&
        channelCount == other.channelCount &&
        sampleRate == other.sampleRate &&
        channelFormat == other.channelFormat &&
        sourceId == other.sourceId &&
        uid == other.uid;
  }
}

/// Stream info with full metadata and description access.
///
/// This class extends [LSLStreamInfo] to provide immediate access to the stream's
/// metadata through the [description] property. It represents a "full" stream info
/// object that includes complete XML metadata structure, as opposed to the basic
/// stream info returned by stream resolution.
///
/// **When You Get This Type:**
/// - Creating new streams with `LSL.createStreamInfo()`
/// - After calling `LSL.createInlet()` with `includeMetadata: true`
/// - Reconstructing from XML with `fromXml()`
///
/// **Key Features:**
/// - Immediate [description] access without additional network calls
/// - Full XML metadata structure for complex stream annotations
/// - All methods from base [LSLStreamInfo] class
///
/// **Metadata Usage:**
/// ```dart
/// final streamInfo = await LSL.createStreamInfo(
///   streamName: 'EEG_Stream',
///   channelCount: 32,
/// );
///
/// final description = streamInfo.description;
/// final root = description.value;
///
/// // Add manufacturer and channel info
/// root.addChildValue('manufacturer', 'BioSemi');
/// final channels = root.addChildElement('channels');
/// for (int i = 0; i < 32; i++) {
///   final ch = channels.addChildElement('channel');
///   ch.addChildValue('label', 'CH${i + 1}');
/// }
/// ```
///
/// **See Also:**
/// - [LSLStreamInfo] for basic stream information
/// - [LSLDescription] for metadata access patterns
class LSLStreamInfoWithMetadata extends LSLStreamInfo {
  LSLStreamInfoWithMetadata({
    required super.streamName,
    required super.streamType,
    required super.channelCount,
    required super.sampleRate,
    required super.channelFormat,
    required super.sourceId,
    super.streamInfo,
  }) : super();

  /// Create from existing lsl_streaminfo pointer (with metadata)
  factory LSLStreamInfoWithMetadata.fromStreamInfo(lsl_streaminfo streamInfo) {
    final Pointer<Utf8> streamName = lsl_get_name(streamInfo) as Pointer<Utf8>;
    final Pointer<Utf8> streamType = lsl_get_type(streamInfo) as Pointer<Utf8>;
    final int channelCount = lsl_get_channel_count(streamInfo);
    final double sampleRate = lsl_get_nominal_srate(streamInfo);
    final lsl_channel_format_t channelFormat = lsl_get_channel_format(
      streamInfo,
    );
    final Pointer<Utf8> sourceId =
        lsl_get_source_id(streamInfo) as Pointer<Utf8>;
    final String streamTypeString = streamType.toDartString();
    return LSLStreamInfoWithMetadata(
      streamName: streamName.toDartString(),
      streamType: LSLContentType.values.firstWhere(
        (e) => e.value == streamTypeString,
        orElse: () => LSLContentType.custom(
          streamTypeString,
        ), // Default to Custom if not found
      ),
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: LSLChannelFormat.values.firstWhere(
        (e) => e.lslFormat == channelFormat,
        orElse: () =>
            LSLChannelFormat.float32, // Default to float32 if not found
      ),
      sourceId: sourceId.toDartString(),
      streamInfo: streamInfo,
    );
  }

  factory LSLStreamInfoWithMetadata.fromStreamInfoAddr(int address) {
    final streamInfo = lsl_streaminfo.fromAddress(address);
    if (streamInfo.isNullPointer) {
      throw LSLException('Invalid stream info address');
    }
    return LSLStreamInfoWithMetadata.fromStreamInfo(streamInfo);
  }

  /// Access to the stream's metadata/description
  LSLDescription get description {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created or destroyed');
    }
    return LSLDescription(_streamInfo!);
  }

  @override
  LSLStreamInfoWithMetadata create() {
    if (!created) {
      super.create();
    }
    return this;
  }

  @override
  void destroy() {
    // Use parent's destroy implementation
    super.destroy();
  }

  @override
  String toString() {
    return 'LSLStreamInfoWithMetadata[$uid]{streamName: $streamName, streamType: $streamType, channelCount: $channelCount, sampleRate: $sampleRate, channelFormat: $channelFormat, sourceId: $sourceId, host: $hostname}';
  }

  @override
  int get hashCode => Object.hash(
    _streamInfo?.address,
    streamName,
    streamType,
    channelCount,
    sampleRate,
    channelFormat,
    sourceId,
    uid,
  );

  @override
  operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLStreamInfoWithMetadata) return false;
    return super == other;
  }
}
