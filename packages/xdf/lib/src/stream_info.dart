import 'package:xml/xml.dart';

import 'format.dart';

/// One channel as a stream header describes it (`desc/channels/channel`).
class XdfChannel {
  final String label;
  final String unit;
  final String type;

  const XdfChannel({this.label = '', this.unit = '', this.type = ''});
}

String _text(XmlElement? e, String name) =>
    e?.getElement(name)?.innerText.trim() ?? '';

double _double(XmlElement? e, String name) =>
    double.tryParse(_text(e, name)) ?? 0;

/// A stream's header: what LSL says about the stream (its `info` XML).
class XdfStreamInfo {
  final String name;
  final String type;
  final int channelCount;

  /// Samples per second, or 0 for irregular streams (e.g. markers).
  final double nominalRate;
  final XdfFormat format;
  final String sourceId;
  final String hostname;
  final String uid;
  final String sessionId;

  /// LSL clock time at which the stream was created.
  final double createdAt;

  /// The channels from `desc/channels`, if described.
  final List<XdfChannel> channels;

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
    final doc = XmlDocument.parse(xmlText);
    final info = doc.getElement('info') ?? doc.rootElement;
    final desc = info.getElement('desc');
    final channels = [
      for (final c
          in desc?.getElement('channels')?.findElements('channel') ??
              const <XmlElement>[])
        XdfChannel(
          label: _text(c, 'label'),
          unit: _text(c, 'unit'),
          type: _text(c, 'type'),
        ),
    ];
    return XdfStreamInfo._(
      name: _text(info, 'name'),
      type: _text(info, 'type'),
      channelCount: int.tryParse(_text(info, 'channel_count')) ?? 0,
      nominalRate: _double(info, 'nominal_srate'),
      format: XdfFormat.parse(_text(info, 'channel_format')),
      sourceId: _text(info, 'source_id'),
      hostname: _text(info, 'hostname'),
      uid: _text(info, 'uid'),
      sessionId: _text(info, 'session_id'),
      createdAt: _double(info, 'created_at'),
      channels: channels,
      xml: info,
    );
  }

  /// A stream header for writing.
  factory XdfStreamInfo({
    required String name,
    String type = '',
    required int channelCount,
    double nominalRate = 0,
    XdfFormat format = XdfFormat.float32,
    String sourceId = '',
    String hostname = '',
    String uid = '',
    String sessionId = '',
    double createdAt = 0,
    List<XdfChannel> channels = const [],
  }) {
    final b = XmlBuilder();
    b.element(
      'info',
      nest: () {
        void field(String n, Object v) => b.element(n, nest: '$v');
        field('name', name);
        field('type', type);
        field('channel_count', channelCount);
        field('nominal_srate', nominalRate);
        field('channel_format', format.name);
        field('source_id', sourceId);
        field('version', '1.1');
        field('created_at', createdAt);
        field('uid', uid);
        field('session_id', sessionId);
        field('hostname', hostname);
        b.element(
          'desc',
          nest: () {
            if (channels.isEmpty) return;
            b.element(
              'channels',
              nest: () {
                for (final c in channels) {
                  b.element(
                    'channel',
                    nest: () {
                      field('label', c.label);
                      if (c.unit.isNotEmpty) field('unit', c.unit);
                      if (c.type.isNotEmpty) field('type', c.type);
                    },
                  );
                }
              },
            );
          },
        );
      },
    );
    return XdfStreamInfo.parse(b.buildDocument().toXmlString());
  }

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

/// A clock offset measurement: at [time] (the recorder's LSL clock), the
/// stream's clock was [value] seconds behind (add it to the stream's time
/// stamps to get the recorder's time).
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
