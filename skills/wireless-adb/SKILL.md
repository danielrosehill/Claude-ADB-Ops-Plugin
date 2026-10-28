---
name: wireless-adb
description: Connect adb to an Android phone over Wi-Fi (Android 11+ wireless debugging) instead of USB, pair a new host with it, and set up a host (a home server or the workstation) that reconnects to the phone automatically whenever it is on the LAN. Use for "connect to my phone over the network", "wireless adb", "pair adb", "adb over Wi-Fi", "keep adb connected to my phone", or when another adb-ops skill finds no USB device.
---

# adb-ops: wireless-adb

Wireless debugging (Settings → Developer options → Wireless debugging) has three properties
that shape everything below:

1. **Pairing happens once per host.** The phone remembers the host's key (`~/.android/adbkey`
   on that host). After that, `adb connect` needs no code.
2. **The connect port is random** (seen in the 30000–49999 range) and changes each time
   wireless debugging is switched on and after a reboot. The phone advertises it over mDNS as
   `_adb-tls-connect._tcp`, but mDNS often does not cross from a wired host to Wi-Fi clients.
   So find the port with a port scan of the phone's reserved IP instead.
3. **Wireless debugging only runs on Wi-Fi**, and Android switches it off when the phone
   leaves the network. Whether it comes back by itself on return varies by build.
   <!-- FLAG: unconfirmed whether OnePlus/OxygenOS re-enables it automatically on a trusted network -->

The phone needs a **DHCP reservation** so its IP stays fixed. Phones use a randomised
per-network MAC, so reserve against the MAC it shows on this network. On the phone, set that
network's Wi-Fi privacy to the device MAC if the reservation keeps missing.

## Host config

`<workspace>/network.env` on the host that connects (see `../_shared/workspace.md` for
`<workspace>`):

```bash
ADB_HOST=10.0.0.52          # the phone's reserved IP
ADB_FIXED_PORT=5555         # used after `adb tcpip 5555`; harmless if closed
ADB_PORT_RANGE=30000-49999  # where wireless debugging puts its connect port
```

The script writes `<workspace>/network-state.json` with the last port that worked.

## Pair a host (once per host)

Needs the user at the phone:

1. Ask the user to open Wireless debugging → **Pair device with pairing code** and keep that
   dialog open. It shows a 6-digit code and an `IP:port`. The pairing port differs from the
   connect port.
2. On the host: `adb pair <IP>:<pairing-port> <code>`. Expect `Successfully paired`.
3. Connect: run the autoconnect script once, or `adb connect <IP>:<connect-port>` with the
   port shown on the Wireless debugging screen.
4. Check with `adb devices -l`, then run `device-status`.

If pairing fails with a timeout, the dialog was closed or the code expired. Ask for a fresh one.

## Connect now

```bash
adb devices -l                          # already connected?
<skill-dir>/scripts/adb-autoconnect.sh  # fixed port, last port, then scan
```

The skill directory is `${CLAUDE_PLUGIN_ROOT}/skills/wireless-adb`. If that variable is unset
(the skill was read from the catalogue), clone `danielrosehill/Claude-ADB-Ops-Plugin` and use
the path inside it.

Exit codes: `0` connected or phone not on the LAN, `1` phone is up but nothing accepted adb
(wireless debugging off, or this host isn't paired), `2` no config.

## Stay connected (persistent host)

Install on the host as systemd **user** units. The host needs `adb` (Debian/Ubuntu package
`adb`) and `nmap`, plus lingering so the units run without a login session:
`loginctl enable-linger $USER`.

```bash
install -Dm755 scripts/adb-autoconnect.sh ~/.local/bin/adb-autoconnect
install -Dm644 -t ~/.config/systemd/user scripts/systemd/adb-server.service \
  scripts/systemd/adb-autoconnect.service scripts/systemd/adb-autoconnect.timer
adb kill-server   # hand the server over to the unit
systemctl --user daemon-reload
systemctl --user enable --now adb-server.service adb-autoconnect.timer
```

- `adb-server.service` runs `adb server nodaemon` permanently. Without it, the adb server
  would start inside the oneshot unit and systemd would kill it, dropping the connection, as
  soon as the oneshot finished.
- `adb-autoconnect.timer` runs the script every 2 minutes. Logs go to
  `journalctl --user -u adb-autoconnect`.
- Run pairing **after** `adb-server.service` is up, as the same user, so the key and the
  connection belong to that server.

Verified 2026-10-28 on a OnePlus Nord 3 (CPH2493, Android 16) from an Ubuntu 26.04 server: paired, then the scan found the connect port and connected in one run.

Optional, when a fixed port is wanted until the next reboot: once connected,
`adb -s <IP>:<port> tcpip 5555`. adbd restarts on 5555 and the script finds it first. The
port closes on reboot, and the scan takes over again.

## Use from another machine

The adb server listens on localhost only. To run adb on the host from elsewhere, go through
the host (SSH, or a tool that runs commands there). Exposing the adb server to the network
with `adb -a` is not set up.
