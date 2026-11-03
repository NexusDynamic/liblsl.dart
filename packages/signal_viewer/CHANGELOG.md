## 0.2.2

- `SyntheticProvider` and `SyntheticSession`: synthetic test signals made
  in the app and shown as live streams, with markers as a stream of their
  own and simulated dropouts. The provider adds *Test > Synthetic stream…*
  and a button on the welcome screen.
- `SynthForm`, the fields for choosing a synthetic signal, for providers
  that send one elsewhere.
- Requires `signal_core` ^0.3.0.

## 0.2.1

- Live trace and event plots sweep by default: a cursor moves from left to
  right and draws over the previous pass, so the data already drawn stays
  still. The *Live display* chip of a live tab switches it between sweeping
  and scrolling, and Preferences > Appearance sets the choice for new live
  tabs. Spectrograms continue to scroll.
- `ViewSettings.liveDisplay` and `Preferences.liveDisplay` (`LiveDisplay`).

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
