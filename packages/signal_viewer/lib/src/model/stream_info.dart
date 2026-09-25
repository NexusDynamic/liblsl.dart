import 'package:signal_core/signal_core.dart';

/// Display kind of a stream, which decides its defaults and which
/// processing applies.
enum Kind {
  eeg('EEG'),
  emg('EMG'),
  imu('IMU'),
  audio('Audio'),
  event('Event'),
  other('Other');

  final String label;
  const Kind(this.label);
}

/// Map a stream type (a Hyperscanner data type, an LSL stream type) to a
/// display kind.
///
/// Covers the Hyperscanner's data types and the LSL stream types of the
/// LSL wiki's meta-data conventions (e.g. `Markers`, `MoCap`, `Gaze`).
Kind kindFromType(String type) => switch (type.trim().toLowerCase()) {
  'eeg' || 'meg' || 'ieeg' || 'ecog' => Kind.eeg,
  'emg' || 'exg' || 'ecg' || 'eog' || 'ekg' => Kind.emg,
  'imu' ||
  'gyro' ||
  'gyroscope' ||
  'accel' ||
  'acc' ||
  'accelerometer' ||
  'motion' ||
  'mocap' ||
  'orientation' ||
  'position' => Kind.imu,
  'audio' || 'sound' || 'microphone' || 'mic' => Kind.audio,
  'event' ||
  'events' ||
  'markers' ||
  'marker' ||
  'stim' ||
  'stimulus' ||
  'trigger' ||
  'triggers' => Kind.event,
  _ => Kind.other,
};

/// Static description of a stream of multichannel samples: one stream of a
/// source (e.g. a device's port, an LSL stream), or
/// several shown together.
class StreamInfo {
  /// Unique id, e.g. `hs:5` or `group:EEG:500`.
  final String key;
  final String name;

  /// A short name for the stream in the labels of channels merged from
  /// several streams, e.g. `P0` in `P0:ch1`.
  final String tag;

  /// The source's type of the stream (e.g. an LSL stream type such as
  /// `EEG` or `Markers`); empty if it has none.
  final String type;
  final Kind kind;

  /// Nominal sampling rate in Hz, 0 for irregular streams.
  final double rate;

  /// Channel names: the device's, or the user's (Port setup).
  final List<String> labels;

  /// The device's channel labels, e.g. `P0:ch1`, whatever the user named
  /// the channels; empty if the same as [labels].
  final List<String> deviceLabels;

  final List<String> units;

  /// Where each channel comes from.
  final List<ChannelRef> channels;

  const StreamInfo({
    required this.key,
    required this.name,
    String? tag,
    this.type = '',
    required this.kind,
    required this.rate,
    required this.labels,
    this.deviceLabels = const [],
    required this.units,
    required this.channels,
  }) : tag = tag ?? name;

  int get channelCount => labels.length;

  /// The device's label of [channel].
  String deviceLabel(int channel) =>
      channel < deviceLabels.length ? deviceLabels[channel] : labels[channel];

  /// Whether the user named [channel].
  bool renamed(int channel) => deviceLabel(channel) != labels[channel];

  bool get irregular => rate <= 0;

  /// Whether high-pass and notch filtering make sense.
  bool get filterable => (kind == Kind.eeg || kind == Kind.emg) && rate > 0;

  /// Whether channels can be marked bad (EEG/EMG with more than one).
  bool get badChannels =>
      (kind == Kind.eeg || kind == Kind.emg) && channelCount > 1;

  bool get canReference => badChannels && channelCount > 2;

  bool get canMean => kind != Kind.event && channelCount > 1;

  String unit([int channel = 0]) =>
      channel < units.length ? units[channel] : '';

  /// Indices of the streams (e.g. ports) its channels come from.
  List<int> get streamIndices => {for (final c in channels) c.stream}.toList();

  StreamInfo copyWith({
    String? name,
    Kind? kind,
    List<String>? labels,
    List<String>? deviceLabels,
  }) => StreamInfo(
    key: key,
    name: name ?? this.name,
    tag: tag,
    type: type,
    kind: kind ?? this.kind,
    rate: rate,
    labels: labels ?? this.labels,
    deviceLabels: deviceLabels ?? this.deviceLabels,
    units: units,
    channels: channels,
  );
}

String prettyUnit(String unit) => unit.toLowerCase() == 'uv' ? 'µV' : unit;
