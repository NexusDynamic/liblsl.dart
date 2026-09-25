# LSL Viewer: XDF file viewer and Lab Streaming Layer stream viewer

View **XDF recordings** (e.g. from LabRecorder) and **live Lab Streaming
Layer (LSL) streams** on Windows, macOS, Linux, Android and the web.

- **Web app:** <https://nexusdynamic.org/liblsl.dart/lsl_viewer/>. XDF files
  are read in the browser and never uploaded.
- **Downloads:** [`lsl_viewer` releases](https://github.com/NexusDynamic/liblsl.dart/releases?q=lsl_viewer&expanded=true).
  The Linux and Windows archives include the `lsl` command line tool under
  `cli/`, and every desktop OS has a separate `lsl-cli-…` archive. On macOS
  the app is unsigned: right-click it and choose *Open* the first time.

## What it does

- **XDF files** of any size, one tab per stream. Open them with
  *Open recording…*, by dropping them on the window, or on the desktop with
  `lsl_viewer file.xdf`.
- **Live LSL streams** (*LSL > View streams…*), on desktop and Android.
- **Each tab** has filters, re-referencing, power spectra, signal quality
  and trigger decoding. The source setup (View menu) overrides a stream's
  type and channel names.
- **Record** LSL streams to XDF. **Replay** a recording as LSL streams from
  the shown position, or **Forward** one stream (live or recorded) under
  another name.
- **Devices:** the OpenBCI Cyton (+ Daisy), and serial devices that print
  lines of numbers (e.g. an Arduino). They work on the desktop, on Android
  over USB, and in Chrome and Edge with WebSerial.

## LSL in the browser, and across networks

A browser can't use LSL itself, because liblsl needs the system's sockets.
It works through a WebSocket **bridge** instead. The
[bridge and relay guide](../../packages/lsl_tools/doc/relay.md) covers the
setup, security and hosting behind `wss://`.

On a desktop, *LSL > Share or relay streams…* offers three modes:

- **Share:** sends this network's LSL streams to clients (all of them,
  including new ones, or the ones you pick).
- **Share + accept:** also takes streams that clients publish, passes them
  to the other clients, and publishes them as LSL here.
- **Relay only:** passes streams between clients, with no LSL involved.

The panel shows the `ws://` addresses to connect to, and lists the
connected clients and streams.

Anywhere, including the web, *LSL > Connect to an LSL bridge…* connects to
one of those, or to `lsl share` / `lsl relay`:

- **View** opens a stream in a tab.
- With a bridge that accepts streams, *Forward…* and *Replay this recording
  from here* publish through it. For example, a Cyton on WebSerial, or an
  XDF file replayed in the browser.
- On a desktop, *Publish its streams on LSL here* does what
  `lsl bridge` does.

The hosted web app is an `https://` page, so browsers only let it connect to
`wss://` addresses, or to `ws://localhost` on the same computer.

## Building

It is `signal_viewer` with three source providers: `LslProvider`
(`signal_viewer_lsl`), `XdfProvider` (`signal_viewer_xdf`) and
`SerialStreamProvider` (`signal_viewer_serial`).

```sh
flutter run -d linux            # or macos, windows, chrome, a device
flutter run -d linux -a recording.xdf
```

### App icon

The icons are generated from the images in `assets/icon/`:

- `icon.png`: 1024×1024.
- `icon_square.png`: the same with square corners and no transparency, for
  iOS.
- `foreground.png`: Android's adaptive icon. Keep the art in the middle
  ~66%.

To change the icon, replace those images and run:

```sh
dart run flutter_launcher_icons
```

Linux uses `assets/icon/icon.png` directly: it is installed in the bundle as
`data/icon.png`, along with `data/lsl_viewer.desktop`. Check the diff of
`ios/Runner.xcodeproj/project.pbxproj` afterwards: the generator changes
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`, which should
stay `YES`.
