import 'dart:typed_data';

import 'package:signal_viewer/signal_viewer.dart';

import 'lsl.dart';
import 'lsl_session.dart';

/// Re-publishes a stream received in [session] as a new LSL stream: under
/// another name, optionally with only some [channels] and with [derived]
/// processing (re-referencing, high-pass and notch filters, applied as the
/// samples arrive). Time stamps are passed on as received.
class LslForward {
  final LslSession session;
  final LslOutlet outlet;

  /// Channels of the session's stream that are sent, in order.
  final List<int> channels;
  final DerivedSpec derived;
  final SosStreamFilter? _filter;
  int sent = 0;
  late final void Function(LslChunk) _tap = _onChunk;

  LslForward._(this.session, this.outlet, this.channels, this.derived)
    : _filter = derived.filters && session.info.rate > 0
          ? SosStreamFilter(
              Sos.display(
                session.info.rate,
                highpass: derived.highpass,
                notch: derived.notch,
              ),
              session.info.channelCount,
            )
          : null {
    session.taps.add(_tap);
  }

  /// Start forwarding [session] as [name].
  static Future<LslForward> start(
    LslSession session, {
    required String name,
    List<int>? channels,
    DerivedSpec derived = DerivedSpec.none,
    LslOutletOptions options = const LslOutletOptions(),
  }) async {
    final info = session.info;
    final stream = session.inlet.stream;
    final strings = stream.format.isString;
    final chosen = strings
        ? const [0]
        : (channels ?? [for (var c = 0; c < info.channelCount; c++) c]);
    final outlet = await lsl.createOutlet(
      LslOutletSpec(
        name: name,
        type: stream.type,
        channelCount: chosen.length,
        rate: info.irregular ? 0 : info.rate,
        format: strings ? LslFormat.string : LslFormat.float32,
        sourceId:
            'forward:${stream.sourceId.isEmpty ? stream.uid : stream.sourceId}:$name',
        channels: [
          for (final c in chosen)
            LslChannel(info.labels[c], unit: info.unit(c)),
        ],
        desc: {
          'forwarded': {
            'from': stream.name,
            'source_id': stream.sourceId,
            'hostname': stream.hostname,
            if (derived.highpass > 0) 'highpass_hz': '${derived.highpass}',
            if (derived.notch > 0) 'notch_hz': '${derived.notch}',
            if (derived.references) 'rereferenced': 'true',
          },
        },
      ),
      options,
    );
    return LslForward._(
      session,
      outlet,
      chosen,
      strings ? DerivedSpec.none : derived,
    );
  }

  String get name => outlet.spec.name;

  void _onChunk(LslChunk c) {
    if (c.length == 0) return;
    if (c.strings != null) {
      outlet.pushStrings([
        for (var i = 0; i < c.length; i++)
          c.strings![i * session.info.channelCount],
      ], c.times);
      sent += c.length;
      return;
    }
    final n = session.info.channelCount;
    final values = c.values!;
    final m = c.length;
    List<Float64List>? cols;
    if (derived.references || _filter != null) {
      cols = [
        for (var ch = 0; ch < n; ch++)
          Float64List(m)
            ..setAll(0, [for (var i = 0; i < m; i++) values[i * n + ch]]),
      ];
      if (derived.references) applyReference(cols, derived);
      final f = _filter;
      if (f != null) {
        for (var ch = 0; ch < n; ch++) {
          f.process(ch, cols[ch]);
        }
      }
    }
    final out = Float32List(m * channels.length);
    for (var i = 0; i < m; i++) {
      for (var k = 0; k < channels.length; k++) {
        final ch = channels[k];
        out[i * channels.length + k] = cols == null
            ? values[i * n + ch]
            : cols[ch][i];
      }
    }
    outlet.push(out, c.times);
    sent += m;
  }

  Future<void> close() async {
    session.taps.remove(_tap);
    await outlet.close();
  }
}
