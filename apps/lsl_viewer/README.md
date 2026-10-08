# LSL Viewer: XDF file viewer and Lab Streaming Layer stream viewer

LSL Viewer displays XDF recordings, such as those written by LabRecorder,
and live Lab Streaming Layer (LSL) streams. It runs on Windows, macOS,
Linux, Android and the web.

The [web app](https://nexusdynamic.org/liblsl.dart/lsl_viewer/) reads XDF
files locally in the browser. Version
[0.2.0](https://github.com/NexusDynamic/liblsl.dart/releases/tag/lsl_viewer-v0.2.0)
is available for Windows, macOS, Linux and Android
([all releases](https://github.com/NexusDynamic/liblsl.dart/releases?q=lsl_viewer&expanded=true)).
The Linux and Windows archives include the `lsl` command line tool under
`cli/`, and each desktop platform also has a separate `lsl-cli-…` archive.
The macOS build is unsigned and is opened the first time through the context
menu (right-click, *Open*).

<p align="center">
    <a href="../../lsl_and_xdf_viewer_screenshot.png">
    <img src="../../lsl_and_xdf_viewer_screenshot.png" alt="screenshot of the LSL viewer showing the recorded EEG from an XDF file" height="450px">
    </a>
    <a href="../../android_lsl_and_xdf_viewer.png">
        <img src="../../android_lsl_and_xdf_viewer.png" alt="screenshot of the LSL viewer android app showing the recorded EEG from an XDF file" height="450px">
    </a>
</p>

## Functions

| Function | Description |
| --- | --- |
| XDF recordings | Files of any size, with one tab per stream. A file is opened with *Open recording…*, by dropping it on the window, or on the desktop with `lsl_viewer file.xdf` |
| Live LSL streams | *LSL > View streams…*, on desktop platforms and Android |
| Signal display | Each tab has filters, re-referencing, power spectra, signal quality and trigger decoding. The source setup (View menu) overrides the type and channel names of a stream |
| Recording and replay | LSL streams are recorded to XDF. A recording is replayed as LSL streams from the position shown, and a single stream, live or recorded, can be forwarded under another name |
| Devices | The OpenBCI Cyton (with or without Daisy), and serial devices that print lines of numbers, such as an Arduino. They are supported on desktop platforms, on Android over USB, and in Chrome and Edge with WebSerial |

## LSL in the browser and across networks

A browser cannot use LSL directly, because liblsl requires the sockets of
the operating system. LSL streams reach a browser, or another network,
through a WebSocket bridge. The
[bridge and relay guide](../../packages/lsl_tools/doc/relay.md) covers the
setup, security and hosting behind `wss://`.

On a desktop, *LSL > Share or relay streams…* offers three modes:

| Mode | Behaviour |
| --- | --- |
| Share | Sends the LSL streams of this network to clients: all of them, including new ones, or a selection |
| Share + accept | Also accepts streams that clients publish, passes them to the other clients, and publishes them as LSL on this network |
| Relay only | Passes streams between clients, without LSL |

The panel shows the `ws://` addresses to connect to, and lists the connected
clients and streams.

On every platform, including the web, *LSL > Connect to an LSL bridge…*
connects to such a bridge, or to one started with `lsl share` or
`lsl relay`. A stream of the bridge is opened in a tab with *View*. With a
bridge that accepts streams, *Forward…* and *Replay this recording from
here* publish through it; a Cyton connected by WebSerial, or an XDF file
replayed in the browser, can be published in this way. On a desktop,
*Publish its streams on LSL here* has the effect of `lsl bridge`.

The hosted web app is an `https://` page, so browsers allow it to connect
only to `wss://` addresses, or to `ws://localhost` on the same computer.

## Building

The application is `signal_viewer` with three source providers: `LslProvider`
(`signal_viewer_lsl`), `XdfProvider` (`signal_viewer_xdf`) and
`SerialStreamProvider` (`signal_viewer_serial`).

```sh
flutter run -d linux            # or macos, windows, chrome, a device
flutter run -d linux -a recording.xdf
```

### App icon

The application uses the NexusDynamic icon that all applications in this
repository share. The source images are in
[`packages/nexus_branding/assets/icon`](../../packages/nexus_branding/assets/icon),
and [`flutter_launcher_icons.yaml`](./flutter_launcher_icons.yaml) describes
how the platform icons are generated from them:

```sh
dart run flutter_launcher_icons
```

Linux has no generator. The bundle installs `icon.png` from the same folder
as `data/icon.png`, along with `data/lsl_viewer.desktop`. The generator
changes `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in
`ios/Runner.xcodeproj/project.pbxproj`; the value should remain `YES`, so
that change is reverted afterwards.
