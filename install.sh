#!/bin/bash
# cleanup — one-shot installer.
# Works two ways:
#   1. Local: `bash install.sh` from inside a cloned repo.
#   2. Remote: `curl -fsSL https://raw.githubusercontent.com/xodn348/cleanup/main/install.sh | bash`
#      In remote mode, this script clones itself to ~/code/cleanup first.
#
# Idempotent. Safe to re-run.

set -e
TARGET="${CLEANUP_HOME:-$HOME/code/cleanup}"

# Self-bootstrap: if we're piped in (no sibling files), clone first.
if [[ ! -f "$TARGET/cleanup-logger.sh" ]]; then
  echo "→ cloning https://github.com/xodn348/cleanup → $TARGET"
  git clone --quiet https://github.com/xodn348/cleanup.git "$TARGET"
fi

PROJECT_ROOT="$TARGET"
SETTINGS="$HOME/.claude/settings.json"

echo "→ chmod +x scripts"
chmod +x "$PROJECT_ROOT"/*.sh

echo "→ mount /cleanup skill into ~/.claude/skills/"
mkdir -p "$HOME/.claude/skills"
ln -sfn "$PROJECT_ROOT/skill" "$HOME/.claude/skills/cleanup"

echo "→ wire hooks into $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
# Follow a symlink so we edit the real file (some setups symlink settings.json).
if [[ -L "$SETTINGS" ]]; then
  SETTINGS="$(readlink -f "$SETTINGS" 2>/dev/null || readlink "$SETTINGS")"
  echo "    (following symlink to $SETTINGS)"
fi
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

LOGGER="bash $PROJECT_ROOT/cleanup-logger.sh"
ALERT="bash $PROJECT_ROOT/stale-tools-alert.sh"

python3 - "$SETTINGS" "$LOGGER" "$ALERT" <<'PY'
import json, sys, pathlib
path, logger_cmd, alert_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
data = json.loads(p.read_text() or "{}")
hooks = data.setdefault("hooks", {})

def has(event, cmd):
    for group in hooks.get(event, []):
        for h in group.get("hooks", []):
            if h.get("command") == cmd:
                return True
    return False

def add(event, cmd):
    if has(event, cmd):
        print(f"    {event}: already wired")
        return
    hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": cmd}]})
    print(f"    {event}: added")

add("PostToolUse", logger_cmd)
add("SessionStart", alert_cmd)
p.write_text(json.dumps(data, indent=2) + "\n")
PY

echo
echo "✓ installed. Start a new Claude Code session — the logger begins collecting."
echo "  After 30 days of normal use, Claude will surface stale tools and suggest /cleanup."
