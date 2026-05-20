# cleanup

A small tool that watches which Claude Code skills and MCPs you actually use,
and reminds you to clean up the ones you don't. It never deletes anything on
its own.

## Why I built this

Claude Code got slow. Not the model — the *session*. After a few months of
installing skills, MCP servers, and plugins from blog posts and one-off
experiments, every new session was carrying around ~60 skills and a handful
of MCPs I no longer used. Each one of them shows up in Claude's system
prompt at startup, eats context, and clutters the tool-selection menu.

The natural fix — "just remove the ones you don't use" — never happens
because nobody remembers *which* are still useful. cleanup gives you that
signal: it watches what you actually call, and at most once a week it tells
you which tools have gone quiet for over a month. You decide what to keep.

## Quick start

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

Start a new Claude Code session — that's it. After 30 days of normal use,
Claude will start surfacing stale tools at the top of new sessions and
suggest `/cleanup`. You can also run it manually any time:

```bash
bash ~/code/cleanup/audit-stale-tools.sh
cat ~/code/cleanup/data/stale-tools.md
```

## Architecture

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

## How it works

Three small pieces:

1. **A logger.** Every time Claude calls a tool (a skill, an MCP, anything),
   `cleanup-logger.sh` writes one line to a log file. That's the data.

2. **A reporter.** `audit-stale-tools.sh` reads the log, asks Claude Code
   which skills and MCPs are currently installed, and classifies each as
   *used*, *stale* (30+ days quiet), or *never used*.

3. **A nudge.** On each new Claude session, `stale-tools-alert.sh` checks
   the report. If anything is stale, it drops a one-line note into Claude's
   context: *"these tools haven't been used in 30+ days — run /cleanup if
   you want to review them."*

The `/cleanup` skill then walks you through the list one entry at a time.
Skills get moved to an `.archive/` folder (reversible). MCPs are removed
with `claude mcp remove`. Nothing happens without you saying yes.

Two safety rules:

- **30-day grace period.** Right after install, the log is empty, so
  everything looks unused. The nudge stays silent until tracking has been
  running long enough that "never used" means something.
- **7-day cooldown.** At most one reminder per week. No nagging.

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
