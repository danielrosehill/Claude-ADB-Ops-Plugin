---
name: onboard
description: First-run onboarding for the adb-ops plugin. Interview the user about the Android device connected via ADB — model, Android version, rooted status — then collect folder mappings (phone path to local path, with labels and use cases). Writes profile and mappings to the adb-ops workspace at <workspace>/. Use this before any other adb-ops skill, or whenever the user wants to add a new phone folder mapping.
---

# adb-ops: onboard

Establish the persistent profile for a phone the user manages via ADB.

## Migration from legacy path (one-time)

Before resolving the workspace, check for legacy data at `~/.claude/adb-ops/`. If the legacy directory exists AND the new workspace is empty, move every file (`profile.yaml`, `mappings.yaml`, `bloatware-log.jsonl`, `devices/`) to the new location and delete the legacy directory. Tell the user: "Migrated adb-ops workspace from ~/.claude/adb-ops/ to <new>."

## Workspace resolution

Resolve the workspace directory as `$CLAUDE_USER_DATA/adb-ops/` if `CLAUDE_USER_DATA` is set; otherwise `$XDG_DATA_HOME/claude-plugins/adb-ops/` if `XDG_DATA_HOME` is set; otherwise `~/.local/share/claude-plugins/adb-ops/`. Create the directory if it doesn't exist. See the canonical convention in the `rudder:plugin-data-storage` skill. Referred to as `<workspace>/` throughout this plugin.

## When to use

- User says "set up adb", "onboard my phone", "add a new phone mapping".
- Any other adb-ops skill finds no `<workspace>/profile.yaml` — ask the user whether to run onboarding first.

## Prerequisites

- `adb` installed on the host (`which adb`). If missing, tell the user how to install it (`sudo apt install adb` on Debian/Ubuntu) and stop.
- Phone connected and USB debugging authorised. Run `adb devices` — if the device shows `unauthorized`, prompt the user to accept the dialog.

## Procedure

1. **Create workspace** at `<workspace>/` if it does not exist.

2. **Detect device** and pre-fill what ADB already knows:

   ```bash
   adb devices -l
   adb shell getprop ro.product.manufacturer
   adb shell getprop ro.product.model
   adb shell getprop ro.build.version.release
   adb shell su -c id 2>/dev/null   # rooted check — if exit 0 and uid=0, rooted
   ```

3. **Interview** the user for anything ADB can't auto-detect:
   - Friendly name for the device (e.g. "daily driver").
   - Rooted status — confirm the detected answer.
   - Free-text notes (warranty, primary use, SIM carrier).

4. **Collect folder mappings** — loop until the user says they're done. For each:
   - Label (kebab-case, e.g. `camera-photos`).
   - Phone path (e.g. `/sdcard/DCIM/Camera`). Verify it exists: `adb shell ls -d <path>`.
   - Local path on this computer (e.g. `~/Pictures/Phone/Camera`). Create it if missing and the user agrees.
   - Use case (one sentence — "why does this mapping exist").
   - Direction: `pull` (default), `push`, or `bidirectional`.

   Suggest common starter mappings if the user asks: camera photos (`/sdcard/DCIM/Camera`), screenshots (`/sdcard/Pictures/Screenshots`), downloads (`/sdcard/Download`), voice recorder (`/sdcard/Recordings`).

5. **Write** `profile.yaml` and `mappings.yaml` following the schema in `skills/_shared/workspace.md`. Use `captured_at` with ISO-8601 local time.

6. **Summary**: print the profile and mappings back to the user, show the workspace path, and list the sibling skills they can now invoke (`device-status`, `take-screenshot`, `import-media`, `remove-bloatware`, `bloatware-log`, `pull-folder`, `push-folder`).

## Re-running

If `profile.yaml` already exists, offer three paths:
- **Update device info** (overwrite profile).
- **Add mappings** (append to `mappings.yaml`).
- **Replace everything** (confirm, back up the old files with `.bak` suffix first).

Never silently overwrite existing mappings.
