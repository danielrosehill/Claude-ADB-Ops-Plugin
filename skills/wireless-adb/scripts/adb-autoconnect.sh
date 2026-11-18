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
ADB_AUTOPIN_HOSTS="${ADB_AUTOPIN_HOSTS:-}"   # phones to move onto ADB_FIXED_PORT (adb tcpip) after a random-port connect

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

# pin <host> <port>: after connecting on a random wireless-debugging port, switch adbd to ADB_FIXED_PORT,
# which survives wireless debugging being switched off (not a reboot). Opt-in per host: on some phones/builds
# tcpip over wireless kills wireless debugging and 5555 never opens (OnePlus 2026-10-28), so only list hosts
# where it was tested to work AND something on the phone (e.g. KeepADB) turns wireless debugging back on.
pin() {
  case " $ADB_AUTOPIN_HOSTS " in *" $1 "*) ;; *) return 0 ;; esac
  [ "$2" = "$ADB_FIXED_PORT" ] && return 0
  log "$1: pinning adbd to port $ADB_FIXED_PORT (was $2)"
  timeout 10 adb -s "$1:$2" tcpip "$ADB_FIXED_PORT" >/dev/null 2>&1
  timeout 3 adb disconnect "$1:$2" >/dev/null 2>&1
  local i; for i in 1 2 3 4 5 6; do sleep 2; try "$1" "$ADB_FIXED_PORT" && return 0; done
  log "$1: port $ADB_FIXED_PORT did not open after tcpip; waiting for wireless debugging to come back"
  return 1
}

reconnect() {  # reconnect <host>; 0 = connected or not on the LAN, 1 = up but no port accepted adb
  local h="$1" last p
  connected "$h" && { prune "$h"; return 0; }
  ping -c1 -W2 "$h" >/dev/null 2>&1 || return 0   # phone not on the LAN; nothing to do
  # 1. fixed port (only open after `adb tcpip`), 2. last port that worked, 3. scan the range
  last=$(sed -n 's/.*"port":\([0-9]*\).*/\1/p' "$(state_file "$h")" 2>/dev/null)
  for p in "$ADB_FIXED_PORT" $last; do try "$h" "$p" && { pin "$h" "$p"; return 0; }; done
  for p in $(nmap -Pn -n -T4 --min-rate 3000 -p "$ADB_PORT_RANGE" --open -oG - "$h" 2>/dev/null \
              | grep -o '[0-9]*/open' | cut -d/ -f1); do
    [ "$p" = "$last" ] && continue
    try "$h" "$p" && { pin "$h" "$p"; return 0; }
  done
  prune "$h"
  log "phone at $h is up but no port accepted adb (wireless debugging off, or this host not paired)"
  return 1
}

rc=0
for h in $HOSTS; do reconnect "$h" || rc=1; done
exit $rc
