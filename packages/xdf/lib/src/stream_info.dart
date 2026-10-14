import 'package:lsl_core/lsl_core.dart';
import 'package:xml/xml.dart';

/// One channel as a stream header describes it (`desc/channels/channel`).
@Deprecated('Use LSLChannel (package:lsl_core)')
typedef XdfChannel = LSLChannel;

String _text(XmlElement? e, String name) => xmlField(e, name);

double _double(XmlElement? e, String name) =>
    double.tryParse(_text(e, name)) ?? 0;

/// A stream's header: what LSL says about the stream (its `info` XML).
class XdfStreamInfo {
  final String name;
  final String type;
  final int channelCount;

  /// Samples per second, or 0 for irregular streams (e.g. markers).
  final double nominalRate;
  final LSLChannelFormat format;
  final String sourceId;
  final String hostname;
  final String uid;
  final String sessionId;

  /// LSL clock time at which the stream was created.
  final double createdAt;

  /// The channels from `desc/channels`, if described.
  final List<LSLChannel> channels;

  /// The whole `info` element, e.g. for other `desc` fields.
  final XmlElement xml;

  XdfStreamInfo._({
    required this.name,
    required this.type,
    required this.channelCount,
    required this.nominalRate,
    required this.format,
    required this.sourceId,
    required this.hostname,
    required this.uid,
    required this.sessionId,
    required this.createdAt,
    required this.channels,
    required this.xml,
  });

  /// Parse a stream header's XML.
  factory XdfStreamInfo.parse(String xmlText) {
    final info = infoElement(xmlText);
    return XdfStreamInfo._(
      name: _text(info, 'name'),
      type: _text(info, 'type'),
      channelCount: int.tryParse(_text(info, 'channel_count')) ?? 0,
      nominalRate: _double(info, 'nominal_srate'),
      format: LSLChannelFormat.parse(_text(info, 'channel_format')),
      sourceId: _text(info, 'source_id'),
      hostname: _text(info, 'hostname'),
      uid: _text(info, 'uid'),
      sessionId: _text(info, 'session_id'),
      createdAt: _double(info, 'created_at'),
      channels: channelsOf(info),
      xml: info,
    );
  }

  /// A stream header for writing.
  factory XdfStreamInfo({
    required String name,
    String type = '',
    required int channelCount,
    double nominalRate = 0,
    LSLChannelFormat format = LSLChannelFormat.float32,
    String sourceId = '',
    String hostname = '',
    String uid = '',
    String sessionId = '',
    double createdAt = 0,
    List<LSLChannel> channels = const [],
  }) => XdfStreamInfo.parse(
    buildInfoXml(
      name: name,
      type: type,
      channelCount: channelCount,
      rate: nominalRate,
      format: format,
      sourceId: sourceId,
      createdAt: createdAt,
      uid: uid,
      sessionId: sessionId,
      hostname: hostname,
      channels: channels,
    ),
  );

  bool get regular => nominalRate > 0;

  /// The label of channel [c]: from `desc/channels`, or `ch<c + 1>`.
  String label(int c) => c < channels.length && channels[c].label.isNotEmpty
      ? channels[c].label
      : 'ch${c + 1}';

  String unit(int c) => c < channels.length ? channels[c].unit : '';

  /// The header's XML, as written to a file.
  String toXmlString() =>
      '<?xml version="1.0"?>${xml.toXmlString(pretty: false)}';

  @override
  String toString() =>
      'XdfStreamInfo($name, $type, $channelCount ch, $nominalRate Hz, '
      '${format.name})';
}

/// A clock offset measurement: at [time] on the stream's own clock, that
/// clock was [value] seconds behind the recorder's (add it to the stream's
/// time stamps to get the recorder's time).
///
/// [time] is the file's `CollectionTime`. LabRecorder writes the recorder's
/// clock at the measurement minus the offset, which is the stream's clock,
/// and readers (pyxdf, and this package) evaluate the line they fit through
/// the offsets at the stream's time stamps. A writer that has the recorder's
/// clock has to subtract [value] from it.
class XdfClockOffset {
  final double time;
  final double value;

  const XdfClockOffset(this.time, this.value);
}

/// A stream's footer, written when recording stops.
class XdfStreamFooter {
  final double? firstTimestamp;
  final double? lastTimestamp;
  final int? sampleCount;
  final List<XdfClockOffset> clockOffsets;
  final XmlElement xml;

  XdfStreamFooter._(
    this.firstTimestamp,
    this.lastTimestamp,
    this.sampleCount,
    this.clockOffsets,
    this.xml,
  );

  factory XdfStreamFooter.parse(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    final info = doc.getElement('info') ?? doc.rootElement;
    return XdfStreamFooter._(
      double.tryParse(_text(info, 'first_timestamp')),
      double.tryParse(_text(info, 'last_timestamp')),
      int.tryParse(_text(info, 'sample_count')),
      [
        for (final o
            in info.getElement('clock_offsets')?.findElements('offset') ??
                const <XmlElement>[])
          XdfClockOffset(_double(o, 'time'), _double(o, 'value')),
      ],
      info,
    );
  }

  /// Footer XML for writing.
  static String build({
    required double firstTimestamp,
    required double lastTimestamp,
    required int sampleCount,
    List<XdfClockOffset> clockOffsets = const [],
  }) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0"');
    b.element(
      'info',
      nest: () {
        b.element('first_timestamp', nest: '$firstTimestamp');
        b.element('last_timestamp', nest: '$lastTimestamp');
        b.element('sample_count', nest: '$sampleCount');
        b.element(
          'clock_offsets',
          nest: () {
            for (final o in clockOffsets) {
              b.element(
                'offset',
                nest: () {
                  b.element('time', nest: '${o.time}');
                  b.element('value', nest: '${o.value}');
                },
              );
            }
          },
        );
      },
    );
    return b.buildDocument().toXmlString();
  }
}
