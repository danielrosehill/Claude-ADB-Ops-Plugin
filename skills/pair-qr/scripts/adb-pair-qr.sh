#!/usr/bin/env bash
# Pair this host with an Android phone by QR code (wireless debugging, Android 11+), then connect.
#
# The host invents a service name and password and shows them as a QR code. The phone scans it
# and advertises _adb-tls-pairing._tcp under that name. The host finds that service and runs
# `adb pair`, the same flow as Android Studio's "Pair devices using Wi-Fi".
#
# The QR is printed as text. Nothing else opens unless --open asks for an image viewer (--no-open is the default, kept for old callers).
#
# Usage: adb-pair-qr.sh [--timeout SECONDS] [--open] [--name NAME]
# Exit:  0 paired and connected, 1 phone never appeared or pairing failed,
#        2 missing dependency or bad argument, 3 paired but not connected
set -u

TIMEOUT=120 OPEN=0 NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --open)    OPEN=1; shift ;;
    --no-open) OPEN=0; shift ;;
    --name)    NAME="${2:?--name needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for dep in adb qrencode; do
  command -v "$dep" >/dev/null || { echo "missing dependency: $dep" >&2; exit 2; }
done

WS="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/adb-ops"
CONF="${ADB_OPS_NETWORK_CONF:-$WS/network.env}"
ADB_HOST="" ADB_PORT_RANGE="30000-49999"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

log() { echo "adb-pair-qr: $*"; }
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }

# Alphanumeric only, so nothing needs escaping in the WIFI: payload.
[ -n "$NAME" ] || NAME="adb-ops-$(rand 8)"
PASSWORD="$(rand 16)"
PAYLOAD="WIFI:T:ADB;S:$NAME;P:$PASSWORD;;"

if [ -t 1 ]; then qrencode -t ANSIUTF8 -m 2 "$PAYLOAD" || exit 2; else qrencode -t UTF8 -m 2 "$PAYLOAD" || exit 2; fi
if [ "$OPEN" = 1 ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && command -v xdg-open >/dev/null; then
  PNG="${XDG_RUNTIME_DIR:-/tmp}/adb-pair-qr-$$.png"
  trap 'rm -f "$PNG"' EXIT
  qrencode -o "$PNG" -s 10 -m 4 "$PAYLOAD" || exit 2
  xdg-open "$PNG" >/dev/null 2>&1 &
  log "QR code opened in an image viewer: $PNG"
fi
log "on the phone: Wireless debugging > Pair device with QR code. Waiting ${TIMEOUT}s for service $NAME"

# Print "ip:port" for a service type, optionally only for one instance name or one IP.
# adb's own mDNS client comes first; avahi catches what it misses.
discover() {
  local type="$1" want_name="${2:-}" want_ip="${3:-}"
  {
    timeout 3 adb mdns services 2>/dev/null \
      | awk -v t="$type" -v n="$want_name" 'index($0,t) && (n=="" || index($1,n)==1) {print $NF}'
    command -v avahi-browse >/dev/null && timeout 4 avahi-browse -rpt "$type" 2>/dev/null \
      | awk -F';' -v n="$want_name" '$1=="=" && $3=="IPv4" && (n=="" || index($4,n)==1) {print $8":"$9}'
  } | grep -E '^[0-9.]+:[0-9]+$' | { if [ -n "$want_ip" ]; then grep -F "$want_ip:"; else cat; fi; } | sort -u
}

open_ports() {
  command -v nmap >/dev/null || return 0
  nmap -Pn -n -T4 --min-rate 3000 -p "$ADB_PORT_RANGE" --open -oG - "$1" 2>/dev/null \
    | grep -o '[0-9]*/open' | cut -d/ -f1
}

pair() {
  local out
  out=$(timeout 10 adb pair "$1" "$PASSWORD" 2>&1)
  case "$out" in
    *"Successfully paired"*) log "paired with $1"; return 0 ;;
    *) log "pair attempt on $1 failed: $out"; return 1 ;;
  esac
}

connected() { adb devices | awk -v h="$1:" 'index($1,h)==1 && $2=="device"{f=1} END{exit !f}'; }

PHONE_IP=""
deadline=$((SECONDS + TIMEOUT))
started=$SECONDS
last_scan=0
while [ "$SECONDS" -lt "$deadline" ] && [ -z "$PHONE_IP" ]; do
  for target in $(discover _adb-tls-pairing._tcp "$NAME"); do
    pair "$target" && { PHONE_IP="${target%:*}"; log "found by mDNS"; break; }
  done
  # mDNS may not reach this host (wired host, Wi-Fi phone). With a known phone IP, probe its ports.
  if [ -z "$PHONE_IP" ] && [ -n "$ADB_HOST" ] && [ $((SECONDS - started)) -ge 20 ] && [ $((SECONDS - last_scan)) -ge 15 ]; then
    last_scan=$SECONDS
    for port in $(open_ports "$ADB_HOST"); do
      pair "$ADB_HOST:$port" && { PHONE_IP="$ADB_HOST"; log "found by port scan of ADB_HOST"; break; }
    done
  fi
  [ -n "$PHONE_IP" ] || sleep 2
done

if [ -z "$PHONE_IP" ]; then
  log "not paired after ${TIMEOUT}s: any failed attempts are logged above; with none, the QR was not scanned, the phone is on another network, or mDNS is blocked"
  exit 1
fi

# adb may connect by itself once paired. Otherwise find the connect port, which differs from the pairing port.
for _ in 1 2 3 4 5 6 7 8; do
  connected "$PHONE_IP" && break
  for target in $(discover _adb-tls-connect._tcp "" "$PHONE_IP"); do
    timeout 6 adb connect "$target" >/dev/null 2>&1
  done
  connected "$PHONE_IP" && break
  sleep 2
done
if ! connected "$PHONE_IP"; then
  for port in $(open_ports "$PHONE_IP"); do
    timeout 6 adb connect "$PHONE_IP:$port" >/dev/null 2>&1
    connected "$PHONE_IP" && break
    timeout 3 adb disconnect "$PHONE_IP:$port" >/dev/null 2>&1
  done
fi

if connected "$PHONE_IP"; then
  log "connected: $(adb devices | awk -v h="$PHONE_IP:" 'index($1,h)==1 && $2=="device"{print $1; exit}')"
  exit 0
fi
log "paired with $PHONE_IP but could not connect; use the port on the Wireless debugging screen"
exit 3
