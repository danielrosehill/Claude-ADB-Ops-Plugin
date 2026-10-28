#!/usr/bin/env bash
# Reconnect adb to a phone over Wi-Fi (wireless debugging) whenever it is reachable.
# Reads <workspace>/network.env. Safe to run often: it exits at once if the phone is already connected.
set -u
WS="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/adb-ops"
CONF="${ADB_OPS_NETWORK_CONF:-$WS/network.env}"
[ -r "$CONF" ] || { echo "no config at $CONF" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONF"
: "${ADB_HOST:?ADB_HOST not set in $CONF}"
ADB_FIXED_PORT="${ADB_FIXED_PORT:-5555}"
ADB_PORT_RANGE="${ADB_PORT_RANGE:-30000-49999}"
STATE="$WS/network-state.json"

log() { echo "adb-autoconnect: $*"; }
connected() { adb devices | awk -v h="$ADB_HOST:" 'index($1,h)==1 && $2=="device"{f=1} END{exit !f}'; }
try() {
  local out
  out=$(timeout 6 adb connect "$ADB_HOST:$1" 2>&1)
  case "$out" in
    *"connected to"*) sleep 1; connected && { log "connected on port $1"; printf '{"host":"%s","port":%s,"at":"%s"}\n' "$ADB_HOST" "$1" "$(date -Is)" > "$STATE"; return 0; } ;;
  esac
  timeout 3 adb disconnect "$ADB_HOST:$1" >/dev/null 2>&1
  return 1
}

connected && exit 0
ping -c1 -W2 "$ADB_HOST" >/dev/null 2>&1 || exit 0   # phone not on the LAN; nothing to do

# 1. fixed port (only open after `adb tcpip`), 2. last port that worked, 3. scan the range
last=$(sed -n 's/.*"port":\([0-9]*\).*/\1/p' "$STATE" 2>/dev/null)
for p in "$ADB_FIXED_PORT" $last; do try "$p" && exit 0; done
for p in $(nmap -Pn -n -T4 --min-rate 3000 -p "$ADB_PORT_RANGE" --open -oG - "$ADB_HOST" 2>/dev/null \
            | grep -o '[0-9]*/open' | cut -d/ -f1); do
  [ "$p" = "$last" ] && continue
  try "$p" && exit 0
done
log "phone at $ADB_HOST is up but no port accepted adb (wireless debugging off, or this host not paired)"
exit 1
