import 'package:flutter/painting.dart';

/// The palette of nexusdynamic.org: its brand purples and the neutrals its
/// pages are built on. The website in `site/style.css` uses the same values.
abstract final class NexusColors {
  static const brand300 = Color(0xFFD8B4FE);
  static const brand400 = Color(0xFFC084FC);
  static const brand500 = Color(0xFFA855F7);
  static const brand700 = Color(0xFF6B21A8);
  static const brand900 = Color(0xFF3C0366);

  /// Page background and text of the dark theme.
  static const zinc950 = Color(0xFF09090B);
  static const zinc900 = Color(0xFF18181B);
  static const zinc800 = Color(0xFF27272A);
  static const zinc200 = Color(0xFFE4E4E7);

  /// Page background and text of the light theme.
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
}
