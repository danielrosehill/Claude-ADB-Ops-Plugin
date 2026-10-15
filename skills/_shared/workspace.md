# adb-ops workspace conventions

All skills in this plugin read/write user state from a single workspace directory. The workspace resolves as `$CLAUDE_USER_DATA/adb-ops/` if `CLAUDE_USER_DATA` is set; otherwise `$XDG_DATA_HOME/claude-plugins/adb-ops/` if `XDG_DATA_HOME` is set; otherwise `~/.local/share/claude-plugins/adb-ops/`. Create the directory if it doesn't exist. See the canonical convention in the `rudder:plugin-data-storage` skill.

Shell form:

```bash
ADB_OPS_WORKSPACE="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/adb-ops"
mkdir -p "$ADB_OPS_WORKSPACE"
```

Referred to below as `<workspace>/`.

```
<workspace>/
├── profile.yaml          # phone model, Android version, rooted status, notes
├── mappings.yaml         # phone path -> local path mappings, with labels + use cases
├── bloatware-log.jsonl   # append-only log of package removals/restorations
└── devices/<serial>/     # per-device overrides (optional)
```

## Migration from legacy path (one-time)

Before using the workspace, check for legacy data at `~/.claude/adb-ops/`. If the legacy directory exists AND the new workspace is empty, move every file (`profile.yaml`, `mappings.yaml`, `bloatware-log.jsonl`, `devices/`) to the new location and delete the legacy directory. Tell the user: "Migrated adb-ops workspace from ~/.claude/adb-ops/ to <new>."

## profile.yaml schema

```yaml
device:
  serial: <adb serial>
  manufacturer: <e.g. Google>
  model: <e.g. Pixel 8>
  android_version: <e.g. 14>
  rooted: true | false
  notes: <free text>
captured_at: <ISO 8601>
```

## mappings.yaml schema

```yaml
mappings:
  - label: camera-photos
    phone_path: /sdcard/DCIM/Camera
    local_path: ~/Pictures/Phone/Camera
    use_case: "Import new camera photos after a trip"
    direction: pull         # pull | push | bidirectional
  - label: voice-memos
    phone_path: /sdcard/Recordings
    local_path: ~/Audio/Voice-Memos
    use_case: "Pull dictations for transcription"
    direction: pull
```

## bloatware-log.jsonl

Append-only newline-delimited JSON. One record per operation.

```json
{"ts":"2026-04-20T10:30:00+03:00","device":"<serial>","action":"uninstall","package":"com.example.bloat","user":0,"method":"pm uninstall --user 0","result":"success","notes":""}
```

Actions: `uninstall`, `disable`, `restore`, `enable`.

## Helpers

- Always `adb devices` first; if multiple devices, require `-s <serial>` and confirm with the user.
- Treat the workspace as the source of truth — re-read it each invocation rather than caching.
- If `<workspace>/` is missing or empty, prompt the user to run the `onboard` skill first.
