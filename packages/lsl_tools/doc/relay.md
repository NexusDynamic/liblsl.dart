# Sharing LSL streams over the network: bridge and relay

Lab Streaming Layer finds streams with multicast, so it only works where
multicast reaches: usually one local network. A web browser can't use LSL
at all, because it has no raw sockets. The **LSL bridge** in `lsl_tools` carries
streams over a WebSocket instead:

- **Across networks:** another building, a VPN, a cloud server.
- **To browsers:** the [web version of LSL Viewer](https://nexusdynamic.org/liblsl.dart/lsl_viewer/)
  can view live streams and publish its own.
- **Between browsers:** as a relay, what one client publishes the others
  receive, e.g. an XDF recording replayed in one browser and viewed in
  another.

You can run it from the **LSL Viewer** desktop app (no command line needed)
or with the **`lsl` command line tool**.

## Contents

- [Which setup do I need?](#which-setup-do-i-need)
- [Getting the tools](#getting-the-tools)
- [Quick start: view lab streams in a browser](#quick-start-view-lab-streams-in-a-browser)
- [Setup 1: streams from one LSL network to another](#setup-1-streams-from-one-lsl-network-to-another)
- [Setup 2: a browser publishes into LSL](#setup-2-a-browser-publishes-into-lsl)
- [Setup 3: a relay between browsers](#setup-3-a-relay-between-browsers)
- [Security: tokens, origins and TLS](#security-tokens-origins-and-tls)
- [Running a relay on a server (wss://)](#running-a-relay-on-a-server-wss)
- [Command reference](#command-reference)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)

## Which setup do I need?

| You want to… | Run this where the streams are | Clients connect with |
| --- | --- | --- |
| See lab streams in a browser | `lsl share` (or viewer: *Share*) | Viewer: *LSL > Connect to an LSL bridge…* |
| Get lab streams into LSL on another network | `lsl share` | `lsl bridge ws://host:8765` (or viewer: *Publish its streams on LSL here*) |
| Get a browser's streams (serial device, replayed XDF) into LSL | `lsl share --accept` (or viewer: *Share + accept*) | Viewer in the browser: *Forward…* or *Replay…* |
| Pass streams between browsers, no LSL anywhere | `lsl relay` (or viewer: *Relay only*) | Viewers: *Connect*, then *Forward*/*Replay* and *View* |
| Send lab streams out to a relay on a server (the lab accepts no incoming connections) | `lsl publish wss://relay…` in the lab | Anyone connected to the relay |

```text
Setup 1   [LSL network A] ──lsl share──▶ ws ──▶ lsl bridge ──▶ [LSL network B]
                                          └───▶ browser (LSL Viewer on the web)

Setup 2   browser ──publish──▶ ws ──▶ lsl share --accept ──▶ [LSL on that computer]
                                                        └──▶ other clients

Setup 3   browser A ──publish──▶ ws ──▶ lsl relay ──▶ ws ──▶ browser B, C, lsl bridge…
          [LSL lab] ──lsl publish──▶ ┘
```

Streams that clients publish are always shared with every other client. On
a *share* or *share + accept* server they also become ordinary LSL streams
on that computer. A *relay* only passes them between clients, so it doesn't
need LSL.

## Getting the tools

- **LSL Viewer (desktop):** download from the
  [releases page](https://github.com/NexusDynamic/liblsl.dart/releases)
  (`lsl_viewer <version>`). The sharing controls are under
  *LSL > Share or relay streams…*.
- **`lsl` command line tool:** each LSL Viewer release also has
  `lsl-cli-<version>-<os>` archives. Unpack one and run `bin/lsl`
  (`bin\lsl.exe` on Windows). Keep the `lib/` folder next to `bin/`, because
  it holds liblsl. The Linux and Windows viewer archives also include it
  under `cli/`.
- **From source:** in a clone of this repository, run
  `dart run lsl_tools:lsl <command>` from `packages/lsl_tools`. Alternatively,
  `dart build cli` builds the same bundle as the releases.

In the examples below, `lsl` means whichever of these you use.

## Quick start: view lab streams in a browser

On a computer on the lab network (where the LSL streams are):

```sh
lsl share --token choose-a-secret
# Sharing EEG, Markers on port 8765 (address 0.0.0.0)
```

Or in LSL Viewer: *LSL > Share or relay streams…*, choose **Share**, set a
token, then click **Share**. The panel lists the addresses to connect to.

Then, in a browser, open LSL Viewer:

- **The same computer:** use the
  [hosted web viewer](https://nexusdynamic.org/liblsl.dart/lsl_viewer/).
  Choose *Connect to an LSL bridge…*, enter `ws://localhost:8765` and the
  token.
- **Another computer:** the hosted viewer is an `https://` page, and
  browsers only let it reach **`wss://`** addresses (see
  [Running a relay on a server](#running-a-relay-on-a-server-wss)). Use the
  desktop viewer, or serve the web build over plain `http://` on your own
  network. A plain `http://` page can connect to `ws://lab-pc:8765`.

Click **View** next to a stream to open it in a tab.

## Setup 1: streams from one LSL network to another

On network A (where the streams are):

```sh
lsl share -s EEG -s Markers --token s3cret
```

- **`-s`** picks streams by name or type, and `*` is a wildcard. Without
  `-s` every stream is shared.
- **`--rescan 5`** also shares matching streams that appear later.
- **In the viewer:** tick *Share every LSL stream, also new ones*.

On network B:

```sh
lsl bridge ws://lab-pc.example.org:8765 --token s3cret --suffix " (lab)"
```

- **What `bridge` does:** it publishes each shared stream as an LSL stream
  on network B, named with the suffix. LabRecorder, your analysis scripts or
  another viewer can then use it as if it were local.
- **It follows the bridge:** streams that appear or go away there appear or
  go away here.
- **In the viewer:** use *Connect to an LSL bridge…*, then switch on
  *Publish its streams on LSL here*.

Port 8765 (or the one you pick with `-p`) must be reachable from network B:
open it in the firewall, forward it on the router, or use a VPN.

## Setup 2: a browser publishes into LSL

On the computer that should receive the streams:

```sh
lsl share --accept --token s3cret
```

In the browser, *Connect to an LSL bridge…* that computer, then:

- **Live device:** open it (e.g. a Cyton over WebSerial) and use
  *LSL > Forward this stream…*, choosing *LSL on &lt;host&gt; (through its
  bridge)*.
- **XDF recording:** open the file, move to where playback should start,
  then either:
  - use *LSL > Replay this recording from here* for every stream, or
  - use *Forward…* on one stream's tab.

The streams appear as LSL streams on the `--accept` computer (look for them
with `lsl list`). Other clients of the bridge see them too.

## Setup 3: a relay between browsers

```sh
lsl relay --token s3cret
```

Every client connects to the relay:

- One publishes, with *Forward…* or *Replay…* as in Setup 2.
- The others see the published stream in *Connect to an LSL bridge…* and
  click **View**.
- `lsl bridge ws://relay:8765` on a native computer turns them into LSL
  streams there.

A relay needs no LSL on its computer, so it can run on a server with no lab
network (next sections). In the viewer, use *Share or relay streams…* and
choose **Relay only**.

## Security: tokens, origins and TLS

The bridge is built for a trusted group, such as a lab or a class. It is not
meant to be exposed to the open internet unattended.

- **Token:** with `--token`, clients must give it to connect. The viewer can
  generate a random one. Anyone who has it can see every stream and publish
  new ones.
- **The token travels in the URL** (`?token=`). Over plain `ws://` anyone on
  the path can read it. Use `wss://` (TLS) outside a network you trust, and
  keep it out of proxy access logs.
- **Origins:** `--allow-origin https://nexusdynamic.org` (repeatable) makes
  browsers on other websites unable to connect. Native clients such as
  `lsl bridge` and the desktop viewer send no origin and are not affected.
- **Binding:** `--host 127.0.0.1` listens only on this computer, which is
  what you want behind a reverse proxy.

## Running a relay on a server (wss://)

Browsers on `https://` pages, including the hosted viewer, need `wss://`.
The bridge speaks plain `ws://`. Put a reverse proxy with a certificate in
front of it.

On the server:

```sh
lsl relay --host 127.0.0.1 --port 8765 --token "$(openssl rand -hex 16)" \
  --allow-origin https://nexusdynamic.org
```

**[Caddy](https://caddyserver.com)** gets and renews the certificate itself.
In the `Caddyfile`:

```caddy
relay.example.org {
    reverse_proxy 127.0.0.1:8765
}
```

**nginx** (with a certificate from e.g. certbot):

```nginx
server {
    listen 443 ssl;
    server_name relay.example.org;
    # ssl_certificate / ssl_certificate_key ...

    location / {
        proxy_pass http://127.0.0.1:8765;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 1h;
        access_log off;   # the token is in the URL
    }
}
```

Clients then connect to `wss://relay.example.org` with the token.

To keep the relay running, use a systemd unit such as:

```ini
[Service]
ExecStart=/opt/lsl-cli/bin/lsl relay --host 127.0.0.1 --token <token>
Restart=always
```

To send a lab's LSL streams to the relay, run this on a lab computer. It
connects out, so the lab needs no open ports:

```sh
lsl publish wss://relay.example.org --token <token> -s EEG -s Markers --rescan 5
```

Everyone connected to the relay then sees them. `lsl bridge
wss://relay.example.org` elsewhere turns them back into LSL streams.

## Command reference

`lsl share` shares LSL streams, and with `--accept` takes published ones.

| Option | Default | Meaning |
| --- | --- | --- |
| `-s, --stream` | all | Streams by name or type (`*` wildcard); repeatable |
| `-p, --port` | 8765 | Port (0: any free port) |
| `--host` | 0.0.0.0 | Address to listen on (`127.0.0.1`: this computer only) |
| `--token` | none | Clients must give it |
| `--allow-origin` | any | Browser origins allowed; repeatable |
| `--accept` | off | Clients may publish streams: shared with the others and published on LSL here |
| `--[no-]local-outlets` | on | With `--accept`, publish clients' streams on LSL here |
| `--relay` | off | Same as `lsl relay` |
| `--rescan` | off | Every this many seconds, also share new matching streams |

`lsl relay` passes streams between clients only. It takes `-p`, `--host`,
`--token` and `--allow-origin`.

`lsl publish <ws://host:port>` publishes LSL streams from here on a
bridge that accepts them (`--accept` or a relay). It takes `-s` (default:
all), `--token` and `--rescan` (see above). It skips streams that came from
a bridge, so they don't go round in circles.

`lsl bridge <ws://host:port>` publishes a bridge's streams on LSL here, and
follows them as they come and go.

| Option | Default | Meaning |
| --- | --- | --- |
| `-s, --stream` | all | Stream names (`*` wildcard); repeatable |
| `--token` | none | The bridge's token |
| `--suffix` | none | Added to the names published here |

`--peer <address>` goes before any command and looks for LSL streams on a
computer multicast doesn't reach, e.g. `lsl --peer 10.0.0.5 share`.

The library API is `LslBridgeServer.start`, `LslBridgeClient.connect` and
`LslBridgeRepublisher.start` in `package:lsl_tools/lsl_tools.dart`. The
protocol (JSON control messages and binary sample frames) is documented in
`lib/src/bridge/protocol.dart`.

## Limitations

- **Values travel as 32-bit floats.** `double64` and `int64` streams lose
  precision, and string streams keep only their first channel.
- **Time stamps:** each client estimates the offset between its clock and
  the server's from pings every 2 s, keeping the fastest round trip of the
  last 10, and converts time stamps to its own clock. Expect accuracy of
  about half the network's round-trip asymmetry, typically well under a
  millisecond on a LAN and a few ms over the internet. Record on the
  computer with the devices when timing matters.
- **No automatic reconnect.** If the connection drops, connect again.
- **Trusted groups only:** see
  [Security](#security-tokens-origins-and-tls).

## Troubleshooting

- **The browser can't connect and the console mentions "mixed content" or
  "insecure":** the page is `https://` and the address is `ws://`. Use
  `wss://` behind a proxy, or `ws://localhost` on the same computer.
- **Connection refused or timed out:** the port is blocked. Check the
  firewall on the sharing computer, and whether it listens on
  `127.0.0.1` only (`--host`).
- **403 Forbidden:** the token is wrong, or the page's origin isn't in
  `--allow-origin`.
- **`lsl share` says *No streams to share.*:** no LSL streams were found in
  2 s. Check with `lsl list`, use `--peer` where multicast doesn't reach, or
  use `--accept`/`relay` to start without any.
- **Chrome asks to allow access to devices on the local network:** this is
  Chrome's Local Network Access check for public pages reaching private
  addresses. Allow it, or use the desktop viewer.
