# nexus_branding

`nexus_branding` just provides shared elements for the apps.

The website in [`site/`](../../site) uses the same colours and icon; its
values are in `site/style.css`.

## Themes

```dart
import 'package:flutter/material.dart';
import 'package:nexus_branding/nexus_branding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeMode = await ThemeModeController.load();
  runApp(
    ThemeModeScope(
      controller: themeMode,
      child: ValueListenableBuilder(
        valueListenable: themeMode,
        builder: (context, mode, _) => MaterialApp(
          themeMode: mode,
          theme: nexusLightTheme(),
          darkTheme: nexusDarkTheme(),
          home: Scaffold(
            appBar: AppBar(actions: const [ThemeModeToggle()]),
          ),
        ),
      ),
    ),
  );
}
```

`ThemeModeController` follows the system setting until the user chooses a
mode, and stores the choice with `shared_preferences`. `ThemeModeToggle` is
a button that moves through system, light and dark.

Applications built on `signal_viewer` pass the two themes in `ViewerConfig`;
the viewer has its own theme button and stores the mode in its preferences.

## Icon

`assets/icon/` contains the images from which the launcher icons of the
applications are generated. They are rendered from `nexusdynamic.svg`, the
logo of [nexusdynamic.org](https://nexusdynamic.org/):

```bash
cd assets/icon
rsvg-convert -w 1024 -h 1024 nexusdynamic.svg -o icon.png
magick icon.png -background '#0a0a0a' -alpha remove -alpha off icon_square.png
```

| File | Use |
| --- | --- |
| `icon.png` | The full icon, 1024×1024, for the web, macOS, Windows and Linux |
| `icon_square.png` | The same without transparency, for iOS |
| `foreground.png` | The foreground of the Android adaptive icon: the logo without its background, at 66% of the canvas |

Each application has a `flutter_launcher_icons.yaml` that refers to these
files; `dart run flutter_launcher_icons` in the application's folder
regenerates its platform icons.
