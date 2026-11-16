#!/usr/bin/env bash
# Reconnect adb to one or more phones over Wi-Fi (wireless debugging) whenever they are reachable.
# Reads <workspace>/network.env: ADB_HOSTS="ip1 ip2 ..." (a pool), or ADB_HOST=ip for a single phone.
# Safe to run often: a phone that is already connected is skipped at once.
set -u
WS="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/adb-ops"
CONF="${ADB_OPS_NETWORK_CONF:-$WS/network.env}"
[ -r "$CONF" ] || { echo "no config at $CONF" >&2; exit 2; }
ADB_HOST="" ADB_HOSTS=""
# shellcheck disable=SC1090
. "$CONF"
HOSTS="${ADB_HOSTS:-$ADB_HOST}"
[ -n "$HOSTS" ] || { echo "neither ADB_HOSTS nor ADB_HOST set in $CONF" >&2; exit 2; }
ADB_FIXED_PORT="${ADB_FIXED_PORT:-5555}"
ADB_PORT_RANGE="${ADB_PORT_RANGE:-30000-49999}"

log() { echo "adb-autoconnect: $*"; }
state_file() { echo "$WS/network-state-$1.json"; }
# Probing non-adb ports can leave "offline" entries behind; drop them.
prune() { adb devices | awk -v h="$1:" 'index($1,h)==1 && $2=="offline"{print $1}' | while read -r d; do timeout 3 adb disconnect "$d" >/dev/null 2>&1; done; }
connected() { adb devices | awk -v h="$1:" 'index($1,h)==1 && $2=="device"{f=1} END{exit !f}'; }
try() {  # try <host> <port>
  local out
  out=$(timeout 6 adb connect "$1:$2" 2>&1)
  case "$out" in
    *"connected to"*) sleep 1; connected "$1" && { prune "$1"; log "$1 connected on port $2"; printf '{"host":"%s","port":%s,"at":"%s"}\n' "$1" "$2" "$(date -Is)" > "$(state_file "$1")"; return 0; } ;;
  esac
  timeout 3 adb disconnect "$1:$2" >/dev/null 2>&1
  return 1
}

# Legacy single-phone state file (before ADB_HOSTS): move it to the per-host name.
if [ -f "$WS/network-state.json" ]; then
  h=$(sed -n 's/.*"host":"\([^"]*\)".*/\1/p' "$WS/network-state.json")
  [ -n "$h" ] && [ ! -f "$(state_file "$h")" ] && mv "$WS/network-state.json" "$(state_file "$h")"
fi

reconnect() {  # reconnect <host>; 0 = connected or not on the LAN, 1 = up but no port accepted adb
  local h="$1" last p
  connected "$h" && { prune "$h"; return 0; }
  ping -c1 -W2 "$h" >/dev/null 2>&1 || return 0   # phone not on the LAN; nothing to do
  # 1. fixed port (only open after `adb tcpip`), 2. last port that worked, 3. scan the range
  last=$(sed -n 's/.*"port":\([0-9]*\).*/\1/p' "$(state_file "$h")" 2>/dev/null)
  for p in "$ADB_FIXED_PORT" $last; do try "$h" "$p" && return 0; done
  for p in $(nmap -Pn -n -T4 --min-rate 3000 -p "$ADB_PORT_RANGE" --open -oG - "$h" 2>/dev/null \
              | grep -o '[0-9]*/open' | cut -d/ -f1); do
    [ "$p" = "$last" ] && continue
    try "$h" "$p" && return 0
  done
  prune "$h"
  log "phone at $h is up but no port accepted adb (wireless debugging off, or this host not paired)"
  return 1
}

rc=0
for h in $HOSTS; do reconnect "$h" || rc=1; done
exit $rc
