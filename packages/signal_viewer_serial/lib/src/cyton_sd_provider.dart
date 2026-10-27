import 'dart:async';

import 'package:openbci_cyton/openbci_cyton.dart';
import 'package:openbci_cyton/xdf.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

import 'sd_target.dart';

/// Opens recordings that an OpenBCI Cyton logged to its SD card
/// (`OBCI_XX.TXT`), as XDF recordings: a tab for the channels (µV), and
/// one for the accelerometer or the markers. The gains are taken to be 24
/// and the rate is estimated from the accelerometer (250 Hz without it).
///
/// The file is read in pieces up to its unused space and converted as it
/// is read, into a temporary file (or memory, on the web).
class CytonSdProvider extends SourceProvider {
  /// Bytes read at a time.
  final int pieceBytes;

  CytonSdProvider({this.pieceBytes = 1 << 20});

  @override
  List<String> get fileExtensions => const ['txt'];

  @override
  Future<SourceSession> openFile(PickedFile file) async {
    final source = file.spec.open();
    try {
      final head = await source.read(0, 4096);
      if (!CytonSdFile.looksLike(head)) {
        throw const FormatException('Not an OpenBCI Cyton SD card recording');
      }
      Stream<List<int>> pieces() async* {
        for (var at = 0; at < source.length; at += pieceBytes) {
          yield await source.read(at, pieceBytes);
        }
      }

      final target = SdTarget.create(file.name);
      final summary = await convertCytonSdToXdf(
        pieces(),
        target.sink,
        name: file.name,
      );
      app.setStatus(
        '${file.name}: ${summary.channelCount} channels, '
        '${summary.duration.toStringAsFixed(1)} s at '
        '${formatNumber(summary.layout.rate)} Hz'
        '${summary.layout.rateEstimated ? ' (estimated)' : ''}'
        '${summary.lost > 0 ? ', ${summary.lost} lost' : ''}',
      );
      return await XdfSession.open(
        file.name,
        await target.finish(),
        path: file.path,
        cacheBytes: app.prefs.cacheMb << 20,
      );
    } finally {
      await source.close();
    }
  }
}
