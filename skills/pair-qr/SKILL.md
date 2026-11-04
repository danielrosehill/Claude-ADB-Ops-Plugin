---
name: pair-qr
description: Pair adb with an Android phone by QR code. Generates a QR code, shows it on the host's screen for the phone to scan under Wireless debugging, then completes the pairing and connects. Use for "pair my phone with a QR code", "show a QR code for wireless debugging", "scan to pair adb", or when a user would rather scan than type a pairing code.
---

# adb-ops: pair-qr

Needs Android 11+, the phone and host on the same network, and `qrencode` on the host
(Debian/Ubuntu package `qrencode`). `avahi-utils` is recommended: `adb mdns services` alone can
miss the phone. `nmap` enables the fallbacks below.

## How it works

Same flow as Android Studio's "Pair devices using Wi-Fi":

1. The host invents a service name and password and encodes them as
   `WIFI:T:ADB;S:<name>;P:<password>;;`.
2. The phone scans the code and advertises `_adb-tls-pairing._tcp` under that name.
3. The host finds the service over mDNS and runs `adb pair <ip>:<port> <password>`.
4. The host connects on the separate connect port, advertised as `_adb-tls-connect._tcp`.

Pairing happens once per host. After that, `adb connect` needs no code (see `wireless-adb`).

## Run it

Tell the user what to do on the phone first, because the script waits for them:
**Settings → Developer options → Wireless debugging → Pair device with QR code**.

```bash
<skill-dir>/scripts/adb-pair-qr.sh            # waits 120 seconds
```

The skill directory is `${CLAUDE_PLUGIN_ROOT}/skills/pair-qr`. If that variable is unset (the
skill was read from the catalogue), clone `danielrosehill/Claude-ADB-Ops-Plugin` and use the
path inside it.

Give the Bash call a timeout above the script's own (150000 ms for the default), or run it in
the background.

**Showing the code.** On a desktop session the script opens a PNG in the default image viewer,
because tool output may not reach the user's screen. The PNG is deleted when the script exits,
and the viewer window stays open until the user closes it. Without a display (SSH, a server),
pass `--no-open` and paste the text QR from the script's output into your reply, in a code
block. The script can't print it until it starts, so run it in the background and read its
output file.

Options: `--timeout SECONDS`, `--no-open`, `--name NAME` (fixed service name, for testing).

Exit codes: `0` paired and connected, `1` phone never appeared or pairing failed, `2` missing
dependency or bad argument, `3` paired but not connected.

Finish with `adb devices -l`, then run `device-status`.

## When it fails

- **Exit 1, no failed attempts logged:** the host never saw the phone. Check that both are on
  the same network and the scan succeeded. Client isolation and guest Wi-Fi block mDNS, and it
  often doesn't cross from a wired host to Wi-Fi clients. If `ADB_HOST` is set in
  `<workspace>/network.env`, the script port-scans that IP after 20 seconds and tries each open
  port, so a known phone IP gets round this. Otherwise, use the pairing code route in
  `wireless-adb`.
- **Exit 3:** pairing worked, and only the connect step failed. Run `adb connect <ip>:<port>`
  with the port on the Wireless debugging screen. Never pair again for this.
- **The phone says it couldn't pair:** the code is single-use, so run the script again.

## Status

Tested 2026-11-04 on Ubuntu with adb 34.0.5 and no phone: the timeout path, and mDNS discovery
against a fake `_adb-tls-pairing._tcp` service published with `avahi-publish`.
<!-- FLAG: not yet run against a real phone; a real scan and pair is unconfirmed -->
