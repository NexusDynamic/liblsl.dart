import 'package:flutter/painting.dart';

/// Evenly spaced hues, like pyqtgraph's `intColor(i, hues=max(n, 8))`.
Color channelColor(int index, int count, {required bool dark}) {
  final hues = count < 8 ? 8 : count;
  return HSVColor.fromAHSV(
    1,
    360.0 * (index % hues) / hues,
    dark ? 170 / 255 : 200 / 255,
    dark ? 1 : 190 / 255,
  ).toColor();
}

const badChannelColor = Color(0xFF969696);

/// Quality flags (as in the Python live viewer).
const flagWarnColor = Color(0xFFFFC800);
const flagBadColor = Color(0xFFFF3030);

// Viridis at 9 stops (matplotlib), interpolated linearly.
const _viridis = [
  Color(0xFF440154),
  Color(0xFF472D7B),
  Color(0xFF3B528B),
  Color(0xFF2C728E),
  Color(0xFF21918C),
  Color(0xFF28AE80),
  Color(0xFF5EC962),
  Color(0xFFADDC30),
  Color(0xFFFDE725),
];

Color viridis(double t) {
  if (t.isNaN) t = 0;
  t = t.clamp(0.0, 1.0);
  final pos = t * (_viridis.length - 1);
  final i = pos.floor().clamp(0, _viridis.length - 2);
  return Color.lerp(_viridis[i], _viridis[i + 1], pos - i)!;
}
