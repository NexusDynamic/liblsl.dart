import 'protocol.dart';

/// What an ADS1299 channel measures (`x` command).
enum CytonInput {
  normal,
  shorted,
  biasMeasure,
  mvdd,
  temperature,
  testSignal,
  biasDrp,
  biasDrn,
}

/// Settings of one channel, as the `x` command sets them. The defaults are
/// the board's (`d`).
class CytonChannelSettings {
  final bool enabled;

  /// 1, 2, 4, 6, 8, 12 or 24.
  final int gain;
  final CytonInput input;

  /// Included in the bias (drive right leg) signal.
  final bool bias;

  /// Connected to SRB1 (a common reference for all channels).
  final bool srb1;

  /// Connected to SRB2 (the usual reference for EEG; off for bipolar EMG).
  final bool srb2;

  const CytonChannelSettings({
    this.enabled = true,
    this.gain = 24,
    this.input = CytonInput.normal,
    this.bias = true,
    this.srb1 = false,
    this.srb2 = true,
  });

  /// Bipolar channels (e.g. EMG): no common reference.
  static const bipolar = CytonChannelSettings(srb2: false);

  /// For measuring impedance, as the OpenBCI GUI sets a channel: gain 1,
  /// no reference.
  static const impedance = CytonChannelSettings(gain: 1, srb2: false);

  CytonChannelSettings copyWith({
    bool? enabled,
    int? gain,
    CytonInput? input,
    bool? bias,
    bool? srb1,
    bool? srb2,
  }) => CytonChannelSettings(
    enabled: enabled ?? this.enabled,
    gain: gain ?? this.gain,
    input: input ?? this.input,
    bias: bias ?? this.bias,
    srb1: srb1 ?? this.srb1,
    srb2: srb2 ?? this.srb2,
  );

  /// The `x` command that sets channel [channel] (1-16) to these settings:
  /// x (channel, power down, gain, input, bias, SRB2, SRB1) X, as the
  /// OpenBCI SDK documents it. The default is x1060110X.
  String commandFor(int channel) {
    if (!cytonGains.contains(gain)) {
      throw ArgumentError.value(gain, 'gain', 'One of $cytonGains');
    }
    int b(bool v) => v ? 1 : 0;
    return 'x${cytonChannelChar(channel)}${b(!enabled)}'
        '${cytonGains.indexOf(gain)}${input.index}${b(bias)}'
        '${b(srb2)}${b(srb1)}X';
  }

  @override
  bool operator ==(Object other) =>
      other is CytonChannelSettings &&
      other.enabled == enabled &&
      other.gain == gain &&
      other.input == input &&
      other.bias == bias &&
      other.srb1 == srb1 &&
      other.srb2 == srb2;

  @override
  int get hashCode => Object.hash(enabled, gain, input, bias, srb1, srb2);

  @override
  String toString() => commandFor(1);
}

/// The character that addresses channel [channel] (1-16) in commands.
String cytonChannelChar(int channel) {
  if (channel < 1 || channel > 16) {
    throw RangeError.range(channel, 1, 16, 'channel');
  }
  return channel <= 8 ? '$channel' : 'QWERTYUI'[channel - 9];
}

/// The command that switches channel [channel] (1-16) on or off, without
/// changing its other settings.
String cytonChannelSwitch(int channel, bool on) {
  if (channel < 1 || channel > 16) {
    throw RangeError.range(channel, 1, 16, 'channel');
  }
  final i = (channel - 1) % 8;
  if (channel <= 8) return on ? '!@#\$%^&*'[i] : '12345678'[i];
  return on ? 'QWERTYUI'[i] : 'qwertyui'[i];
}

/// Sampling rates of the ADS1299 (`~` command). The dongle carries 250 Hz
/// at most: the board does not stream at higher rates, which are for
/// logging to the SD card.
enum CytonSampleRate {
  hz250(250, '6'),
  hz500(500, '5'),
  hz1000(1000, '4'),
  hz2000(2000, '3'),
  hz4000(4000, '2'),
  hz8000(8000, '1'),
  hz16000(16000, '0');

  final int hz;
  final String code;
  const CytonSampleRate(this.hz, this.code);

  /// The rate closest to [hz] (by ratio).
  static CytonSampleRate nearest(double hz) {
    var best = hz250;
    for (final r in values) {
      if ((r.hz / hz - 1).abs() < (best.hz / hz - 1).abs() ||
          (hz / r.hz - 1).abs() < (hz / best.hz - 1).abs()) {
        best = r;
      }
    }
    return best;
  }

  /// The rate of exactly [hz] Hz, or null.
  static CytonSampleRate? of(num hz) {
    for (final r in values) {
      if (r.hz == hz) return r;
    }
    return null;
  }
}

/// What the board sends in the 6 aux bytes of its packets (`/` command).
enum CytonBoardMode {
  /// The accelerometer.
  defaults('0', 'default'),

  /// As [defaults], with debug output on the board's external serial port.
  debug('1', 'debug'),

  /// The analog pins A5, A6 and A7 (D11, D12, D13).
  analog('2', 'analog'),

  /// The digital pins D11, D12, D13, D17 and D18.
  digital('3', 'digital'),

  /// Markers sent with [CytonBoard.marker]; the accelerometer is off.
  marker('4', 'marker');

  final String code;

  /// The name in the board's replies.
  final String reply;
  const CytonBoardMode(this.code, this.reply);
}

/// Space reserved on the SD card for a recording: the command letter, and
/// the time it lasts at 250 Hz. Recording longer than reserved loses the
/// rest; stopping earlier keeps what was written.
enum CytonSdDuration {
  min5('A', 5),
  min15('S', 15),
  min30('F', 30),
  hour1('G', 60),
  hour2('H', 120),
  hour4('J', 240),
  hour12('K', 720),
  hour24('L', 1440),

  /// About 14 seconds, for testing.
  test('a', 0.23);

  final String code;

  /// Minutes at 250 Hz.
  final double minutes;
  const CytonSdDuration(this.code, this.minutes);

  /// The smallest reservation that holds [minutes] at [rate], with some
  /// margin (as BrainflowCyton reserves it); throws if none does.
  static CytonSdDuration forMinutes(
    double minutes, [
    CytonSampleRate rate = CytonSampleRate.hz250,
  ]) {
    // About 1.2 MB per minute at 250 Hz.
    final mb = minutes * 1.2 / 250 * rate.hz;
    const limits = [
      (5, min5),
      (16, min15),
      (33, min30),
      (66, hour1),
      (132, hour2),
      (265, hour4),
      (799, hour12),
      (1500, hour24),
    ];
    for (final (limit, d) in limits) {
      if (mb < limit) return d;
    }
    throw ArgumentError(
      '${minutes.toStringAsFixed(0)} minutes at ${rate.hz} Hz needs more '
      'than 1.5 GB of the SD card',
    );
  }
}

/// The board's internal test signals, applied to all channels.
enum CytonTestSignal {
  /// Inputs connected to ground: the system's noise.
  ground('0', 'Ground (noise)'),
  pulse1xSlow('-', 'Square wave, 1×, slow'),
  pulse1xFast('=', 'Square wave, 1×, fast'),

  /// A DC level, for measuring the DC bias.
  dc('p', 'DC'),
  pulse2xSlow('[', 'Square wave, 2×, slow'),
  pulse2xFast(']', 'Square wave, 2×, fast');

  final String code;
  final String label;
  const CytonTestSignal(this.code, this.label);
}

/// Printable characters that are safe as markers ([CytonBoard.marker]):
/// none of them is a command. A marker is sent as a backtick and the
/// marker; if the radio loses the backtick, the board takes the marker
/// for a command, so a marker such as `A` (log to the SD card), `b`
/// (stream) or `1` (channel 1 off) can change what the board does.
const cytonSafeMarkerChars = '9fghklmnoBMNOP()+,._|';

/// Whether [value] is safe as a marker: one of [cytonSafeMarkerChars], or
/// a byte from 128 to 239 (which the board ignores as a command).
bool cytonMarkerIsSafe(int value) =>
    (value >= 0x80 && value <= 0xEF) ||
    cytonSafeMarkerChars.codeUnits.contains(value);

/// A marker for display: its character if printable, else its value.
String cytonMarkerLabel(int value) =>
    value > 0x20 && value < 0x7F ? String.fromCharCode(value) : '$value';

/// Input of a channel that the lead-off current is applied to, for
/// measuring the impedance of the electrode on it: N, the bottom pin, holds
/// the electrode in the usual EEG setup (referenced to SRB2); P is the top
/// pin (e.g. the second electrode of a bipolar channel).
enum CytonLeadOff { p, n }
