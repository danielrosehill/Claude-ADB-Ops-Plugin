# adb-ops

Claude Code plugin for Android Debug Bridge (ADB) operations — onboard a phone, save folder mappings, import media with one command, capture screenshots, and manage bloatware with a persistent, auditable log.

## What it does

`adb-ops` turns a connected Android device into a first-class workspace for Claude Code. You onboard the phone once (model, Android version, rooted status, folder mappings), and from then on you can say "import my camera photos" or "remove the carrier bloat" and Claude knows exactly what you mean.

## Workspace

All user state lives under the `$CLAUDE_USER_DATA/adb-ops/` convention (fallback `$XDG_DATA_HOME/claude-plugins/adb-ops/` or `~/.local/share/claude-plugins/adb-ops/`) — outside `~/.claude/` so the workspace survives plugin updates. See `skills/_shared/workspace.md`:

- `profile.yaml` — device info
- `mappings.yaml` — phone path ↔ local path mappings with labels and use cases
- `bloatware-log.jsonl` — append-only log of every package operation

## Skills

| Skill | Purpose |
|-------|---------|
| `onboard` | First-run interview: device info + folder mappings |
| `device-status` | Snapshot of connected devices, battery, storage |
| `take-screenshot` | Capture and pull a screenshot |
| `import-media` | Pull media from the phone using saved mappings (incremental or full) |
| `remove-bloatware` | Disable or uninstall packages safely, logged to the workspace |
| `bloatware-log` | Browse the bloatware operation history |
| `pull-folder` | Ad-hoc `adb pull` for paths not in mappings |
| `push-folder` | Local-to-device transfer (mapping-driven or ad-hoc) |
| `wireless-adb` | Pair over Wi-Fi (wireless debugging) and keep a host reconnecting automatically (systemd user units) |

## Requirements

- `adb` installed on the host (Linux: `sudo apt install adb`, macOS: `brew install android-platform-tools`).
- Phone with USB debugging enabled and authorised for this computer, or wireless debugging paired with it (`wireless-adb`; also needs `nmap`).

## Installation

```bash
claude plugins marketplace add danielrosehill/Claude-Code-Plugins
claude plugins install adb-ops@danielrosehill
```

## First run

Ask Claude to run the `onboard` skill. Have the phone connected and unlocked.

## License

MIT
