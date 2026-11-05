---
name: pair-qr
description: Pair adb with an Android phone by QR code. Generates a QR code, shows it as text in the conversation for the phone to scan under Wireless debugging, then completes the pairing and connects. Use for "pair my phone with a QR code", "show a QR code for wireless debugging", "scan to pair adb", or when a user would rather scan than type a pairing code.
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

The QR goes in your reply, as text. Nothing opens on the desktop: a viewer window is unwanted (Daniel, 2026-11-05), and tool
output may not reach the user's screen, so the reply is what they scan.

1. Tell the user what to do on the phone, because the script is already waiting once it starts:
   **Settings → Developer options → Wireless debugging → Pair device with QR code**.
2. Start the script in the background (`run_in_background`), with a known phone IP if there is one (see below):

   ```bash
   <skill-dir>/scripts/adb-pair-qr.sh --timeout 180
   ```

3. Read its output file once, straight away. Don't wait for it to finish: it only exits after the scan.
4. Paste the QR block into your reply, in a code block, and say how long it stays valid.
5. When the background task reports exit 0, run `adb devices -l`, then `device-status`.

The skill directory is `${CLAUDE_PLUGIN_ROOT}/skills/pair-qr`. If that variable is unset (the skill was read from the
catalogue), use the local clone, `~/repos/github/ai-agents-and-prompts/ai-claude-plugins/Claude-ADB-Ops-Plugin` (five levels
down, so a shallow `find` misses it). Clone `danielrosehill/Claude-ADB-Ops-Plugin` only if that is missing.

**A known phone IP.** Give the script one, so it has the port-scan fallback when mDNS doesn't reach the host. Setting
`ADB_HOST` in the environment does nothing: the script resets it, and reads it only from the config file. Write the file and
point at it, or use `<workspace>/network.env`:

```bash
echo 'ADB_HOST=10.0.0.52' > ~/.cache/adb-ops/network.env
ADB_OPS_NETWORK_CONF=$HOME/.cache/adb-ops/network.env <skill-dir>/scripts/adb-pair-qr.sh --timeout 180
```

Household phone IPs are in `devices.json` in the `android-phone-manager` plugin.

Options: `--timeout SECONDS` (default 120), `--open` (also show a PNG in the default image viewer, only if the user asks),
`--name NAME` (fixed service name, for testing). `--no-open` is accepted and does nothing.

Exit codes: `0` paired and connected, `1` phone never appeared or pairing failed, `2` missing dependency or bad argument,
`3` paired but not connected. The log says how the phone was found: `found by mDNS` or `found by port scan of ADB_HOST`.

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

Confirmed 2026-11-05 on a real phone: OnePlus Nord 3 (CPH2493), Android 16, host Ubuntu with adb 34.0.5. Paired and connected
on the first scan, exit 0, with `ADB_HOST` set. The pairing and connect ports differed (33067 and 35783), as expected. That run
predates the `found by` log line, so which route found the phone was not recorded.

Tested 2026-11-04 with no phone: the timeout path, and mDNS discovery against a fake `_adb-tls-pairing._tcp` service published
with `avahi-publish`.
