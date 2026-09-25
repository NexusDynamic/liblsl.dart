import 'dart:math' as math;
import 'dart:typed_data';

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

  const CytonSample(this.sampleNumber, this.eeg, this.accel, {this.lost = 0});
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

  /// Gain of each channel (16), for scaling.
  final List<int> gains;

  final _buffer = <int>[];
  final _accel = Float64List(3);
  Float64List? _upper;
  int _lastNumber = -1;

  /// Packets dropped (bad end byte, or a Daisy packet without its pair).
  int dropped = 0;

  CytonDecoder({this.daisy = false, List<int>? gains})
    : gains = gains ?? List.filled(16, 24);

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
    return CytonSample(number, eeg, Float64List.fromList(_accel), lost: lost);
  }
}

/// Encode a sample as a packet (for tests and simulated boards): [eeg] in
/// µV for channels 1-8 (or 9-16 of a Daisy pair), [accel] in g.
Uint8List encodeCytonPacket(
  int number,
  List<double> eeg, {
  List<double>? accel,
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
  out[32] = cytonEndStandard;
  return out;
}
