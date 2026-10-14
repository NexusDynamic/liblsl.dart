import 'package:xml/xml.dart';

import 'facade/types.dart' show LSLChannel;
import 'format.dart';

/// The text of [e]'s child [name], trimmed; empty if there is none.
String xmlField(XmlElement? e, String name) =>
    e?.getElement(name)?.innerText.trim() ?? '';

/// The `info` element of a stream's info XML (or the root, for a fragment).
XmlElement infoElement(String xml) {
  final doc = XmlDocument.parse(xml);
  return doc.getElement('info') ?? doc.rootElement;
}

/// The field [name] of a stream's info XML (`name`, `hostname`,
/// `created_at`...), or empty if it has none or is not valid XML.
String infoField(String xml, String name) {
  if (xml.isEmpty) return '';
  try {
    return xmlField(infoElement(xml), name);
  } on XmlException {
    return '';
  }
}

/// The channels `desc/channels` of an `info` element describes.
List<LSLChannel> channelsOf(XmlElement info) => [
  for (final c
      in info
              .getElement('desc')
              ?.getElement('channels')
              ?.findElements('channel') ??
          const <XmlElement>[])
    LSLChannel(
      xmlField(c, 'label'),
      unit: xmlField(c, 'unit'),
      type: xmlField(c, 'type'),
    ),
];

/// A stream's info XML, as LSL and XDF write it (no `<?xml?>` prolog).
/// [desc] adds `<desc><group><key>value</key></group></desc>` beside the
/// channels.
String buildInfoXml({
  required String name,
  String type = '',
  required int channelCount,
  double rate = 0,
  LSLChannelFormat format = LSLChannelFormat.float32,
  String sourceId = '',
  String version = '1.1',
  double createdAt = 0,
  String uid = '',
  String sessionId = '',
  String hostname = '',
  List<LSLChannel> channels = const [],
  Map<String, Map<String, String>> desc = const {},
}) {
  final b = XmlBuilder();
  void field(String n, Object v) => b.element(n, nest: '$v');
  b.element(
    'info',
    nest: () {
      field('name', name);
      field('type', type);
      field('channel_count', channelCount);
      field('nominal_srate', rate);
      field('channel_format', format.name);
      field('source_id', sourceId);
      field('version', version);
      field('created_at', createdAt);
      field('uid', uid);
      field('session_id', sessionId);
      field('hostname', hostname);
      b.element(
        'desc',
        nest: () {
          if (channels.isNotEmpty) {
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
          }
          for (final g in desc.entries) {
            b.element(
              g.key,
              nest: () {
                for (final e in g.value.entries) {
                  if (e.value.isNotEmpty) field(e.key, e.value);
                }
              },
            );
          }
        },
      );
    },
  );
  return b.buildDocument().rootElement.toXmlString();
}
