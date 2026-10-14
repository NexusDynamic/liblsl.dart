## 0.2.0

- Samples are shown as recorded: live buffers, events and windows keep
  64-bit values (`EventSamples.channels` is `List<List<double>>`).
- Preferences > Memory: *Store samples as 32-bit floats* saves memory for
  recordings opened afterwards; the status bar says when it is on.
- `SourceSession.exactSamples` and `channelFormat`, for playing a
  recording back exactly; `SourceSession.precisionWarning`, shown as a
  warning on the tab (e.g. 64-bit integers in a browser).
- Requires `signal_core` ^0.2.0.

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
