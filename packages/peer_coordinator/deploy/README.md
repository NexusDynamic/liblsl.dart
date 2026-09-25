# Deploying the coordination hub

A `docker compose` stack: [Caddy](https://caddyserver.com) terminates TLS on the
public edge and proxies to the hub, which publishes no ports at all.

> **This is research software.** Everyone holding the session secret is fully
> trusted: they can see every peer and subscribe to every stream. It is built to
> run a session between people you chose, not to survive the open internet
> unattended. Do not put a hub somewhere you would mind it being taken over.

## Quick start

```sh
cd packages/peer_coordinator/deploy
cp .env.example .env

# Mint a secret and paste it into .env as HUB_SECRET.
docker compose run --rm --entrypoint /app/hub hub --generate-secret

# Do the same for HUB_ADMIN_TOKEN, and set HUB_DOMAIN and HUB_SESSION.
$EDITOR .env

docker compose up -d
```

Clients then connect to `wss://$HUB_DOMAIN` with the same `HUB_SESSION` name and
`HUB_SECRET`:

```dart
WebSocketTransportConfig(
  hubUri: Uri.parse('wss://game.example.com'),
  credentials: HubCredentials(session: 'my-session', secret: '...'),
)
```

### Trying it locally

Set `HUB_DOMAIN=localhost`. Caddy issues its own certificate; trust its root
once with `docker compose exec caddy caddy trust` and browsers will accept it.

## What protects what

| Concern | What handles it |
| --- | --- |
| Who may join | The hub's HMAC handshake. The secret is an HMAC key and never crosses the wire. |
| Confidentiality of traffic | Caddy's TLS. The hub speaks plain `ws://` and never terminates TLS. |
| Reaching the hub directly | Nothing publishes its port. It exists only on the compose network. |
| Oversized frames | `--max-frame-bytes`, **in the hub**. See the note below. |
| Ending a session | `--session-ttl`, the admin API, or `docker compose attach hub`. |

**A proxy does not cap WebSocket frames.** Neither Caddy nor nginx does — their
request-body limits stop applying once a connection is upgraded. The frame cap
lives in the hub, where the Dart SDK rejects an oversized frame at its length
header, before any payload is buffered. Do not assume the proxy is a backstop
for it.

## Ending a session

Ending a session disconnects everyone and refuses further logins. Participants
cannot rejoin — that is the point.

**On a schedule.** Set `HUB_SESSION_TTL` in `.env` to a number of seconds. The
hub ends the session on its own when it elapses, whether or not anyone is
watching.

**Interactively.** `docker compose attach hub`, then:

```
status                 session name, epoch, status, connection and peer counts
end                    end it now; everyone is disconnected
open <secret>          reopen for a new cohort with this secret
revoke <nodeUId>       bar one participant, leaving the session running
```

(Detach with `Ctrl-P Ctrl-Q` — `Ctrl-C` would stop the hub.)

**Over the admin API.** Uncomment the `127.0.0.1:9090:9090` port mapping in
`docker-compose.yml`, then:

```sh
curl -X POST http://127.0.0.1:9090/end \
  -H "Authorization: Bearer $HUB_ADMIN_TOKEN"

curl -X POST http://127.0.0.1:9090/open \
  -H "Authorization: Bearer $HUB_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"secret": "a-fresh-secret", "ttlSeconds": 5400}'

curl -X POST http://127.0.0.1:9090/revoke \
  -H "Authorization: Bearer $HUB_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"nodeUId": "..."}'

curl http://127.0.0.1:9090/status \
  -H "Authorization: Bearer $HUB_ADMIN_TOKEN"
```

The admin API is on its own port, bound to loopback, and never proxied — so it
is not reachable through `$HUB_DOMAIN` however Caddy is configured. Keep it that
way; `HUB_ADMIN_TOKEN` can end your session and readmit anyone.

### Reopening does not readmit people by accident

`open` requires a secret, deliberately. Reusing the old one readmits the cohort
you just ejected; pass a fresh one and only people you give it to can return.
The session epoch increments either way, which invalidates any handshake still
in flight from the previous generation.

## Without docker

The hub is one binary. Any reverse proxy works — nginx with
`proxy_set_header Upgrade $http_upgrade` and `proxy_set_header Connection
"upgrade"` on a `location` block is the usual alternative. Keep the two rules
that matter:

1. bind the hub to loopback (`--host 127.0.0.1`, the default) so only the proxy
   can reach it;
2. never expose `--admin-port`.

```sh
dart run peer_coordinator:hub \
  --session my-session --secret-file ./hub.secret \
  --admin-port 9090 --admin-token "$(openssl rand -base64 32)"
```

## Known limits

Deferred, and worth knowing before you rely on this:

- **Any authenticated peer can subscribe to any stream.** Subscription is not
  authorised yet, so the secret is the only boundary — there is none *between*
  peers who hold it.
- **Slot ids are not reused.** They travel as a 16-bit field; past 65535
  registrations in one process the hub refuses new endpoints and asks to be
  restarted, rather than silently misrouting.
- **No `Origin` check.** A web page a participant visits could open a socket to
  the hub. It still cannot authenticate without the secret, but it can consume a
  connection slot.
- **No per-connection rate limit.** A frame cap bounds any single message; a
  fast authenticated peer is not otherwise throttled.
