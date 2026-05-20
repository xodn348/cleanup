# cleanup

A small tool that watches which Claude Code skills and MCPs you actually use,
and reminds you to clean up the ones you don't. It never deletes anything on
its own.

## Why

After a few months of using Claude Code, most people end up with dozens of
skills and MCP servers from one-off experiments. They clutter the menus and
slow Claude down, but nobody remembers which ones are still useful. cleanup
gives you that signal.

## How it works

```
every tool call ──► cleanup-logger.sh ──► events.ndjson
                                                │
                              ┌─────────────────┴─────────────────┐
                              ▼                                   ▼
                     audit-stale-tools.sh                 stale-tools-alert.sh
                     (builds report)                      (nudges Claude on
                                                          new sessions)
                                                                  │
                                                                  ▼
                                                          you run /cleanup
                                                          and decide what
                                                          to archive
```

Three pieces:

1. **A logger.** Every time Claude calls a tool (a skill, an MCP, anything),
   a small script writes one line to a log file. That's the data.

2. **A reporter.** A second script reads the log, asks Claude Code which
   skills and MCPs are currently installed, and classifies each as *used*,
   *stale* (30+ days quiet), or *never used*.

3. **A nudge.** On each new Claude session, a third script checks the
   report. If anything is stale, it drops a one-line note into Claude's
   context: *"these tools haven't been used in 30+ days — run /cleanup if
   you want to review them."*

The `/cleanup` skill then walks you through the list one entry at a time.
Skills are moved to an `.archive/` folder (reversible). MCPs are removed
with `claude mcp remove`. Nothing happens without you saying yes.

## Two safety rules

- **30-day grace period.** Right after install, the log is empty, so
  everything looks unused. The nudge stays silent until you've actually
  been using Claude long enough that "never used" means something.
- **7-day cooldown.** At most one reminder per week. No nagging.

## Install

```bash
git clone https://github.com/xodn348/cleanup.git ~/code/cleanup
chmod +x ~/code/cleanup/*.sh
ln -sfn ~/code/cleanup/skill ~/.claude/skills/cleanup
```

Add these two hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [{
      "hooks": [{ "type": "command",
                  "command": "bash ~/code/cleanup/cleanup-logger.sh" }]
    }],
    "SessionStart": [{
      "hooks": [{ "type": "command",
                  "command": "bash ~/code/cleanup/stale-tools-alert.sh" }]
    }]
  }
}
```

That's it. Start a new Claude Code session and the logger begins collecting.

## Using it

Just keep working in Claude Code normally. After 30 days, if anything is
stale, Claude will mention it at the start of a session and suggest
`/cleanup`. You can also run it manually:

```bash
bash ~/code/cleanup/audit-stale-tools.sh
cat ~/code/cleanup/data/stale-tools.md
```

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `CLEANUP_EVENTS` | `~/code/cleanup/data/events.ndjson` | Log file location |
| `CLAUDE_AUDIT_DAYS` | `30` | How long quiet before "stale" |
| `CLAUDE_AUDIT_COOLDOWN_DAYS` | `7` | Min gap between reminders |

## What it doesn't do

- It doesn't see skills installed via Claude Code plugins (e.g.
  `superpowers:foo`) — those live outside `~/.claude/skills/`.
- It doesn't sync across machines. Each laptop has its own log.
- It doesn't delete or modify anything automatically. Ever.

## License

MIT.
