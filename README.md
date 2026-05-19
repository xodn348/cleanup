# claude-tool-audit

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
