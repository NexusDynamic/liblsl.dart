import 'dart:ffi';
import 'package:ffi/ffi.dart' show StringUtf8Pointer, Utf8, Utf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/structs.dart';
import 'package:liblsl/src/ffi/mem.dart';

extension StreamInfoList on List<LSLStreamInfo> {
  void destroy() {
    for (final streamInfo in this) {
      streamInfo.destroy();
    }
  }
}

class LSLXml {
  /// The XML description of the stream.
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

  /// Adds a child element with text content (like <name>value</name>)
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

  /// Adds a child element (like <name></name>)
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
    if (streamInfo != null) {
      _streamInfo = streamInfo;
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

  factory LSLStreamInfo.fromStreamInfoAddr(int address) {
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
}

/// Stream info with metadata/description access.
/// This class extends LSLStreamInfo to provide access to the stream's metadata.
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
    print(streamName.toDartString());
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
}
