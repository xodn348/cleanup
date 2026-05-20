# cleanup

Passively tracks which Claude Code skills and MCP servers you actually use,
then proactively recommends — but never deletes — anything that has gone
unused for 30+ days.

## How it works

```
PostToolUse (cleanup-logger.sh)
        ↓ appends to
~/code/cleanup/data/events.ndjson           ← data source
        ↓ scanned by
audit-stale-tools.sh                          ← classifies used/stale/never
        ↓ surfaced via
stale-tools-alert.sh (SessionStart hook)      ← proactive nudge
        ↓ resolved by
/cleanup skill                            ← user-driven cleanup
```

- **No auto-delete.** The alert points at the report; only the user (via the skill) chooses what to archive or remove.
- **Grace period (30 days):** alerts stay silent until tracking has been running long enough that "never used" actually means something.
- **Cooldown (7 days):** at most one nudge per week even after grace elapses.

## Wiring

`~/.claude/settings.json` has two relevant hook entries:

- `PostToolUse` → `cleanup-logger.sh` (writes events.ndjson)
- `SessionStart` → `stale-tools-alert.sh` (the proactive nudge)

The skill itself is mounted by symlinking the `skill/` directory into the Claude skills dir:

```bash
ln -sfn ~/code/cleanup/skill ~/.claude/skills/cleanup
```

## Layout

```
cleanup/
├── README.md
├── audit-stale-tools.sh     # report generator
├── stale-tools-alert.sh     # SessionStart nudge
├── skill/
│   └── SKILL.md             # /cleanup skill
└── data/                    # gitignored: tracking-started, last-alert, latest report
```

## Manual use

```bash
bash audit-stale-tools.sh --days 30
cat data/stale-tools.md
```

Or in Claude Code: `/cleanup`.

## Install

Clone, then wire into Claude Code with two hooks and a skill symlink.

```bash
git clone https://github.com/xodn348/cleanup.git ~/code/cleanup
chmod +x ~/code/cleanup/{audit-stale-tools,stale-tools-alert,cleanup-logger}.sh

# Mount the /cleanup skill
ln -sfn ~/code/cleanup/skill ~/.claude/skills/cleanup
```

Then add these two hook entries to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/code/cleanup/cleanup-logger.sh"
      }]
    }],
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/code/cleanup/stale-tools-alert.sh"
      }]
    }]
  }
}
```

The first SessionStart marks the tracking start time. After 30 days of grace,
new sessions get a one-line `additionalContext` nudge if any active tool has
been untouched, then a 7-day cooldown until the next nudge. Run `/cleanup` in
Claude Code anytime to act on the report.

## Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `CLEANUP_EVENTS` | `~/code/cleanup/data/events.ndjson` | Where the logger appends |
| `CLAUDE_AUDIT_DAYS` | `30` | Grace + staleness threshold |
| `CLAUDE_AUDIT_COOLDOWN_DAYS` | `7` | Min days between auto-nudges |
