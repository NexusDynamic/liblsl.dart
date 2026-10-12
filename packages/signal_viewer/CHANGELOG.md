## 0.1.2

- The status bar shows progress of all loading files.
- `AppState.busy(label, work)` shows a label and a progress bar in the
  status bar while a provider works in the background.
- Other tab and open file management improvements.

## 0.1.1

- A theme button in the toolbar switches between the system, light and dark
  themes. The setting is the one in Preferences.
- `ViewerConfig.theme` and `ViewerConfig.darkTheme` replace the themes
  derived from `seedColor` when an application supplies its own.

## 0.1.0

- Initial version, extracted from hyprview 0.5.1: the viewer (tabs, plots,
  controls, dialogs, preferences) with `SourceProvider`s for what it opens.
