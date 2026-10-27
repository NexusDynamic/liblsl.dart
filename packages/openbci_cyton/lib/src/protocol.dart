import 'dart:math' as math;
import 'dart:typed_data';

import 'settings.dart';

/// Start byte of a Cyton data packet.
const cytonStartByte = 0xA0;

/// End bytes: 0xC0 when the aux bytes hold accelerometer data, up to 0xC6.
const cytonEndStandard = 0xC0;
const cytonEndAnalog = 0xC1;
const cytonEndMax = 0xC6;

/// Bytes after the start byte.
const _packetRest = 32;

/// Channel gains of the ADS1299 (`x` command, gain code 0-6).
const cytonGains = [1, 2, 4, 6, 8, 12, 24];

/// Microvolts per count at [gain] (4.5 V reference, 24-bit ADC).
double cytonMicrovolts(int gain) => 4.5 / (math.pow(2, 23) - 1) / gain * 1e6;

/// g per count of the accelerometer.
const cytonAccelScale = 0.002 / 16;

/// One sample: EEG in µV (8 or 16 channels), and the accelerometer in g
/// (the last reading; the board sends it every few packets).
class CytonSample {
  /// The board's counter (0-255; for 16 channels, of the second packet).
  final int sampleNumber;
  final Float64List eeg;
  final Float64List accel;

  /// Samples lost before this one (from gaps in the counter).
  final int lost;

  /// The 6 aux bytes of the packet (for 16 channels, of the second one):
  /// the accelerometer, the pins of the analog or digital board mode, or a
  /// marker.
  final Uint8List aux;

  /// In the marker board mode, the value (1-255) of a marker sent with
  /// this sample (with `CytonBoard.marker`), or null.
  final int? marker;

  CytonSample(
    this.sampleNumber,
    this.eeg,
    this.accel, {
    this.lost = 0,
    Uint8List? aux,
    this.marker,
  }) : aux = aux ?? Uint8List(6);

  /// In the analog board mode, the readings of pins A5, A6 and A7 (D11,
  /// D12, D13), as BrainFlow reads them.
  List<int> get analog => [_int16(aux, 0), _int16(aux, 2), _int16(aux, 4)];
}

int _int24(Uint8List b, int o) {
  final v = (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  return v & 0x800000 != 0 ? v - 0x1000000 : v;
}

int _int16(Uint8List b, int o) {
  final v = (b[o] << 8) | b[o + 1];
  return v & 0x8000 != 0 ? v - 0x10000 : v;
}

/// Turns the bytes a Cyton streams into [CytonSample]s, as BrainFlow does:
/// 33-byte packets (start byte, counter, 8 × 24-bit channels, 6 aux bytes,
/// end byte). With a Daisy ([daisy]), packets come in pairs: an even
/// counter holds channels 9-16, the odd one after it channels 1-8.
class CytonDecoder {
  final bool daisy;

  /// Gain of each channel (16), for scaling. Changing it rescales the
  /// samples that follow.
  final List<int> gains;

  /// What the aux bytes hold.
  final CytonBoardMode mode;

  final _buffer = <int>[];
  final _accel = Float64List(3);
  Float64List? _upper;

  /// A marker from a packet that has not given a sample yet (the first of
  /// a Daisy pair, or one whose pair was lost): the next sample has it.
  int? _marker;
  int _lastNumber = -1;

  /// Packets dropped (bad end byte, or a Daisy packet without its pair).
  int dropped = 0;

  CytonDecoder({
    this.daisy = false,
    List<int>? gains,
    this.mode = CytonBoardMode.defaults,
  }) : gains = gains ?? List.filled(16, 24);

  int get channelCount => daisy ? 16 : 8;

  /// The samples completed by [bytes].
  List<CytonSample> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final out = <CytonSample>[];
    var p = 0;
    while (true) {
      while (p < _buffer.length && _buffer[p] != cytonStartByte) {
        p++;
      }
      if (_buffer.length - p < 1 + _packetRest) break;
      final packet = Uint8List.fromList(
        _buffer.sublist(p + 1, p + 1 + _packetRest),
      );
      final end = packet[31];
      if (end < cytonEndStandard || end > cytonEndMax) {
        // Not a packet after all: look for the next start byte.
        dropped++;
        p++;
        continue;
      }
      p += 1 + _packetRest;
      final s = _packet(packet);
      if (s != null) out.add(s);
    }
    _buffer.removeRange(0, p);
    return out;
  }

  CytonSample? _packet(Uint8List b) {
    final number = b[0];
    // A marker is the first aux value of one packet: a byte, extended to
    // 16 bits with its sign.
    if (mode == CytonBoardMode.marker && b[31] == cytonEndAnalog) {
      if (b[26] != 0) _marker = b[26];
    }
    if (b[31] == cytonEndStandard) {
      final x = _int16(b, 25), y = _int16(b, 27), z = _int16(b, 29);
      // Zeros between readings: keep the last one.
      if (x != 0 || y != 0 || z != 0) {
        _accel[0] = x * cytonAccelScale;
        _accel[1] = y * cytonAccelScale;
        _accel[2] = z * cytonAccelScale;
      }
    }
    final values = Float64List(8);
    for (var i = 0; i < 8; i++) {
      final ch = daisy && number.isEven ? i + 8 : i;
      values[i] = _int24(b, 1 + 3 * i) * cytonMicrovolts(gains[ch]);
    }
    if (daisy && number.isEven) {
      _upper = values;
      return null;
    }
    final upper = _upper;
    _upper = null;
    if (daisy && upper == null) {
      dropped++;
      return null;
    }
    final eeg = Float64List(channelCount)..setAll(0, values);
    if (upper != null) eeg.setAll(8, upper);
    var lost = 0;
    if (_lastNumber >= 0) {
      // The counter counts packets: 2 per sample with a Daisy.
      final step = daisy ? 2 : 1;
      final d = (number - _lastNumber) % 256;
      lost = math.max(0, d ~/ step - 1);
    }
    _lastNumber = number;
    final marker = _marker;
    _marker = null;
    return CytonSample(
      number,
      eeg,
      Float64List.fromList(_accel),
      lost: lost,
      aux: Uint8List.fromList(b.sublist(25, 31)),
      marker: marker,
    );
  }
}

/// Encode a sample as a packet (for tests and simulated boards): [eeg] in
/// µV for channels 1-8 (or 9-16 of a Daisy pair), and either [accel] in g
/// or the raw [aux] bytes, with [endByte].
Uint8List encodeCytonPacket(
  int number,
  List<double> eeg, {
  List<double>? accel,
  List<int>? aux,
  int endByte = cytonEndStandard,
  int gain = 24,
}) {
  final out = Uint8List(33);
  out[0] = cytonStartByte;
  out[1] = number & 0xFF;
  for (var i = 0; i < 8; i++) {
    var v = (eeg[i] / cytonMicrovolts(gain)).round();
    v = v.clamp(-0x800000, 0x7FFFFF);
    final u = v & 0xFFFFFF;
    out[2 + 3 * i] = (u >> 16) & 0xFF;
    out[3 + 3 * i] = (u >> 8) & 0xFF;
    out[4 + 3 * i] = u & 0xFF;
  }
  if (accel != null) {
    for (var i = 0; i < 3; i++) {
      final v = (accel[i] / cytonAccelScale).round().clamp(-32768, 32767);
      final u = v & 0xFFFF;
      out[26 + 2 * i] = (u >> 8) & 0xFF;
      out[27 + 2 * i] = u & 0xFF;
    }
  }
  if (aux != null) out.setRange(26, 32, aux);
  out[32] = endByte;
  return out;
}
