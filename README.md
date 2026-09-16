# ipghost

**Make a remote host answer at a local IP address.**

`ipghost` assigns a "ghost" IP address to your loopback interface and runs a
detached TCP/UDP relay behind it. Everything your machine sends to the ghost
IP is transparently forwarded to a real remote host, and every response is
made to look like it came from the ghost IP. Client software believes it is
talking to a local address — in reality the peer is remote.

```
your app ──▶ 10.99.99.99 (local "ghost" IP)
                 │  ipghost daemon (transparent TCP/UDP relay)
                 ▼
             example.com:443 (real remote host)
             ◀── responses rewritten to come from 10.99.99.99
```

Works on **macOS** and **Linux**. Single-file Python 3 (3.8+), no dependencies.

## Install

Quick install via curl:

```sh
curl -fsSL https://raw.githubusercontent.com/rg1989/ipghost/main/install.sh | sudo sh
```

Or manually:

```sh
curl -fsSL https://raw.githubusercontent.com/rg1989/ipghost/main/ipghost \
  -o /usr/local/bin/ipghost && chmod +x /usr/local/bin/ipghost
```

Or just clone the repo and put `ipghost` on your `PATH`.

## Quick start

```sh
# Configure: make example.com answer at local IP 10.99.99.99 on ports 443+8080
ipghost add 10.99.99.99 example.com --ports 443,8080

# Enable: applies the IP alias and starts the daemon, detached.
# Prompts for sudo only when needed (new alias or privileged port).
ipghost up

# Use it: clients now talk to 10.99.99.99 as if it were local
curl -k https://10.99.99.99/          # actually reaches example.com:443

ipghost status                        # enabled/disabled + counters
ipghost down                          # stop daemon, remove the IP alias
```

## Commands

| command | what it does |
|---|---|
| `ipghost add LOCAL REMOTE --ports SPEC` | add/replace a mapping (see options below) |
| `ipghost remove LOCAL` | remove a mapping |
| `ipghost list` | show configured mappings |
| `ipghost up` | apply IP aliases + start the detached daemon (`--force` restarts) |
| `ipghost down` | stop the daemon + remove IP aliases |
| `ipghost restart` | down + up |
| `ipghost status` | enabled/disabled, per-mapping counters (`--json` for scripts) |
| `ipghost logs [-n N]` | last N lines of the daemon log |

`add` options:

- `--ports SPEC` — ports to relay: `443` or `80,443,8000-8100` (max 8192 ports)
- `--remote-port N` — connect to port N on the remote for all mapped ports
- `--no-udp` — relay TCP only (UDP relay is on by default; covers DNS, QUIC, etc.)

`status` exit codes: `0` running, `3` not running — handy in scripts:
`ipghost status >/dev/null && echo up || echo down`.

## Configuration

Mappings live in `~/.ipghost/config.json` (override with `--config PATH`;
pid/state/log files live alongside the config). The `add`/`remove` commands
edit it for you, but it is plain JSON and safe to edit by hand:

```json
{
  "mappings": [
    {
      "local": "10.99.99.99",
      "remote": "example.com",
      "ports": "443,8080",
      "remote_port": null,
      "udp": true
    },
    {
      "local": "10.10.0.5",
      "remote": "203.0.113.50",
      "ports": "5432",
      "remote_port": 5432,
      "udp": false
    }
  ]
}
```

Runtime files after `up`: `ipghost.pid`, `state.json` (live counters),
`ipghost.log`. Config changes take effect on the next `ipghost up`/`restart`.
A ghost IP may carry several mappings as long as their ports don't overlap —
handy for routing different ports of one "local" address to different
remotes. `ipghost remove <ip>` removes all mappings for that IP.

## How it works

1. `up` assigns each ghost IP to the loopback interface
   (`ifconfig lo0 alias` on macOS, `ip addr add …/32 dev lo` on Linux), so
   the OS treats connections to that IP as local. It records which aliases it
   added so `down` removes exactly those.
2. A detached daemon binds TCP (and optionally UDP) listeners on
   ghost-IP:port for every mapped port and relays bytes to the remote.
   Because the daemon *is* the ghost IP, response rewriting is trivially
   correct — the client's OS sees replies sourced from the ghost IP.
3. When started via sudo the daemon binds its listeners, then drops back to
   your normal user. Remote hostnames are resolved with a 30s cache.

What is preserved: full TCP semantics (including half-close), UDP payloads
byte-for-byte (QUIC works), TLS pass-through. The client's `getpeername()`
returns the ghost IP — that is the point.

## Limitations & gotchas

- **Per-port, not all ports.** You must list the ports you care about
  (userspace relays can't intercept an IP wholesale). Ranges keep this cheap.
- **IPv4 only** for both local and remote, for now.
- **TLS certificate checks**: the remote's cert must match the *name* your
  client uses. Connecting to `https://10.99.99.99/` gets example.com's
  certificate, so use `-k` / add the ghost IP to the cert's SANs / disable
  verification in the client, as appropriate.
- **Protocols that embed IP addresses inside payloads** (FTP active mode,
  SIP, some games) are not rewritten.
- Pick ghost IPs that don't collide with your real networks (e.g. from
  `10.x` RFC1918 space you don't route). On Linux, any `127.x.x.x` ghost IP
  binds without an alias and without sudo (ports ≥ 1024); on macOS only
  `127.0.0.1` itself is bindable unprivileged — every other ghost IP needs
  a loopback alias and therefore sudo.
- Listeners are reachable from this host only (loopback interface).

## Troubleshooting

- **`up` says the daemon failed to start** — see `ipghost logs -n 50`.
  Most often a mapped port is already in use, or the ghost IP collides with
  a real local address.
- **sudo is requested every `up`** — expected whenever a new alias must be
  added or a port < 1024 is mapped. Otherwise ipghost runs unprivileged
  (Linux: any `127.x.x.x`; macOS: `127.0.0.1` only).
- **Stale state after a crash** — `ipghost status` will note leftover
  aliases; run `ipghost down` to clean them up, or `up` to resume.
- `--foreground` on `up` runs the daemon attached to your terminal for
  debugging (`Ctrl-C` stops it cleanly).

## Uninstall

```sh
ipghost down                 # if running
rm -f /usr/local/bin/ipghost
rm -rf ~/.ipghost
```
