---
name: cleanup
description: Use when asked to "cleanup", "find unused tools", "list stale skills", "stale MCPs", "도구 정리", "안 쓰는 스킬" — reports skills/MCPs unused for 30+ days, walks the user through which to remove. Never auto-deletes.
---

# Audit unused tools (skills + MCPs)

## What this does

1. Runs `~/code/cleanup/audit-stale-tools.sh` to refresh the usage report.
2. Shows the user the stale list (kind, name, last-used).
3. For each stale entry, the user decides keep / disable / remove. **Never auto-delete.**
4. If the user wants removals, perform them safely:
   - **Skill**: move `~/.claude/skills/<name>/` to `~/.claude/skills/.archive/<name>-<YYYYMMDD>/` (reversible).
   - **MCP**: `claude mcp remove <name>` and verify with `claude mcp list`.

## Steps

1. Refresh:
   ```bash
   bash ~/code/cleanup/audit-stale-tools.sh --days 30
   ```
2. Read `~/code/cleanup/data/stale-tools.md` and show the stale list grouped by kind.
3. Ask the user which entries to act on (keep / disable / remove).
4. For each removal:
   - Skill → `mv ~/.claude/skills/<name> ~/.claude/skills/.archive/<name>-$(date +%Y%m%d)`
   - MCP → `claude mcp remove <name>`
5. Re-run with `--quiet` so the next session sees a fresh snapshot.

## Notes

- Usage data comes from `~/code/cleanup/data/events.ndjson` (cleanup-logger.sh on PostToolUse).
- If everything reads "never," the PostToolUse hook hasn't been collecting long enough yet — wait through the 30-day grace period before treating the report as authoritative. The SessionStart auto-alert already respects this grace.
- Must not delete anything without explicit per-entry user confirmation.
