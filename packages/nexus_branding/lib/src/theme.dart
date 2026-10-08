import 'package:flutter/material.dart';

import 'colors.dart';

/// The light theme of the applications.
ThemeData nexusLightTheme() => _theme(
  ColorScheme.fromSeed(
    seedColor: NexusColors.brand500,
  ).copyWith(primary: NexusColors.brand700, surface: NexusColors.zinc50),
);

/// The dark theme of the applications, on the near-black of nexusdynamic.org.
ThemeData nexusDarkTheme() => _theme(
  ColorScheme.fromSeed(
    seedColor: NexusColors.brand500,
    brightness: Brightness.dark,
  ).copyWith(
    primary: NexusColors.brand400,
    surface: NexusColors.zinc950,
    surfaceContainerLowest: NexusColors.zinc950,
    surfaceContainerLow: NexusColors.zinc900,
    surfaceContainer: NexusColors.zinc900,
    surfaceContainerHigh: NexusColors.zinc800,
    surfaceContainerHighest: NexusColors.zinc800,
    onSurface: NexusColors.zinc200,
  ),
);

ThemeData _theme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  scaffoldBackgroundColor: scheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: scheme.surface,
    foregroundColor: scheme.onSurface,
  ),
);
