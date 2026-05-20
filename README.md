# cleanup

Passively tracks which Claude Code skills and MCP servers you actually use,
then proactively recommends — but never deletes — anything you have not
touched in 30+ days.

Five shell scripts. No daemon, no database, no dependencies beyond `bash`,
`jq`, and `python3` (already present in any Claude Code environment).

---

## The problem

After a few months on Claude Code, most users have accumulated dozens of
skills and MCP servers from one-off experiments, blog posts, and
`gh repo clone` sessions. They show up in every `/help`, slow down the
autocomplete, and clutter the model's tool-selection prompt — but nobody
remembers which ones they actually use. The natural fix ("just delete the
old ones") never happens because there is no signal for *which* are old.

This is a small, opinionated answer:

- **Passive** — no per-tool annotations, no explicit logging calls.
  A `PostToolUse` hook records every tool invocation as one ndjson line.
- **Proactive but quiet** — a `SessionStart` hook injects a one-line
  reminder into Claude's context *only* when stale items exist, the grace
  period has elapsed, and the cooldown is satisfied.
- **Never destructive** — the recommendation only ever points at the
  report. Removal is gated behind a skill (`/cleanup`) that asks per
  entry and archives instead of deleting.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       Claude Code session                         │
│                                                                   │
│   every tool call ─────────────► PostToolUse hook                 │
│                                       │                           │
└───────────────────────────────────────┼───────────────────────────┘
                                        ▼
                              cleanup-logger.sh
                              (reads tool_name + tool_input.skill)
                                        │
                                        ▼
                              data/events.ndjson
                              ─────────────────
                              {ts, kind:"post_tool", tool, skill}
                              ─────────────────
                                        │
                  ┌─────────────────────┴─────────────────────┐
                  │                                           │
                  ▼                                           ▼
       audit-stale-tools.sh                       stale-tools-alert.sh
       (on demand / from skill)                   (every SessionStart)
                  │                                           │
                  │  1) bucket events by                      │  grace elapsed?
                  │     mcp:<server> or                       │  cooldown ok?
                  │     skill:<name>                          │  stale > 0?
                  │  2) enumerate active tools                │       │
                  │     via `claude mcp list` and             │       ▼
                  │     ~/.claude/skills/*/SKILL.md           │  audit → JSON
                  │  3) classify used / stale / never         │       │
                  ▼                                           ▼
       data/stale-tools.{md,json}              hookSpecificOutput.
                                                additionalContext
                                                ─────────────────
                                                injected into the
                                                model's prompt for
                                                THIS session only
                                                          │
                                                          ▼
                                               user invokes /cleanup
                                                          │
                                                          ▼
                                               skill walks entries
                                                  one by one:
                                                    keep / archive / remove
                                                          │
                                                          ▼
                                          skill: mv → .archive/<name>-<date>
                                          mcp  : `claude mcp remove <name>`
```

---

## Working principle

Three ideas the design hinges on:

**1. The event bus is the source of truth.**
`PostToolUse` is the only hook that fires after every tool call, including
MCP calls and `Skill` invocations. `cleanup-logger.sh` reads the hook's
JSON payload from stdin, extracts `tool_name` and (if it's a `Skill` call)
`tool_input.skill`, and appends one line to `events.ndjson`. Eleven lines
of bash; no buffering, no rotation. The file is append-only, so a partial
write or a killed process cannot corrupt past data.

**2. "Active" is recomputed, never cached.**
`audit-stale-tools.sh` does not maintain a long-lived "registered skills"
list. It enumerates active MCPs by shelling out to `claude mcp list` and
active skills by globbing `~/.claude/skills/*/SKILL.md`. If a skill is
archived, it disappears from the next report automatically.

**3. The model is the UI.**
There is no notification daemon, no menu bar, no separate dashboard.
The `SessionStart` hook emits a JSON object on stdout with shape
`{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: "..."}}`
when (and only when) it has something to say. Claude Code injects that
string into the session's system prompt, so the model itself surfaces
the recommendation in the conversation. The user types `/cleanup` to
act on it — the skill's own SKILL.md is the workflow spec.

---

## Design decisions and their tradeoffs

| Decision | Why | What it gives up |
|---|---|---|
| **30-day grace** before any alert | Right after install, every tool reads "never used" because nothing has been logged yet. The grace prevents a false flood. | First useful alert is 30 days out. |
| **7-day cooldown** between alerts | One nudge per week is informative; one per session is nagging. | Stale items linger longer if the user ignores the first nudge. |
| **No matcher on the `PostToolUse` hook** | The logger needs to see every tool to classify MCP/Skill calls, not just one matcher. | events.ndjson grows linearly with all tool use (~1 KB / 20 tool calls). |
| **Archive, not delete** | `mv` to `.archive/<name>-<YYYYMMDD>/` is one undo away from restoration. | Disk stays slightly larger; user has to clean `.archive/` manually if they want. |
| **`claude mcp list` parsing** | No public API to enumerate MCP servers from a script. | Brittle to CLI output changes; the parser is intentionally minimal (one `grep` + `sed`). |
| **Skill discovery by SKILL.md** | The Claude Code convention is `~/.claude/skills/<name>/SKILL.md`; no central registry. | Plugin-bundled skills (`superpowers:*`) and built-in slash-commands are not tracked — they aren't in that directory. |
| **JSON output, not a TUI** | The audit is consumed by another script (the alert hook) and occasionally by a human reading the .md. A TUI would add 200 lines and a dependency. | No interactive picker; cleanup happens via the model in `/cleanup`. |
| **Per-entry confirmation in the skill** | Recommendation systems that auto-delete have a bad reputation. | Bulk cleanup is slower. (Mitigation: the skill groups by package — gstack, Karpathy personas, etc.) |

---

## Data model

`events.ndjson` — one event per line:

```json
{"ts":"2026-05-20T17:10:21Z","kind":"post_tool","tool":"Bash","skill":""}
{"ts":"2026-05-20T17:10:24Z","kind":"post_tool","tool":"Skill","skill":"cleanup"}
{"ts":"2026-05-20T17:10:31Z","kind":"post_tool","tool":"mcp__readhn__search","skill":""}
```

`stale-tools.json` — the audit output, redrawn from scratch on every run:

```json
{
  "generated_at": "2026-05-20T17:10:35Z",
  "threshold_days": 30,
  "cutoff": "2026-04-20T17:10:35Z",
  "entries": [
    {"kind":"mcp",   "name":"readhn",  "status":"used",  "last_used":"2026-05-19T22:01:08Z"},
    {"kind":"skill", "name":"cleanup", "status":"used",  "last_used":"2026-05-20T17:10:24Z"},
    {"kind":"mcp",   "name":"clawpay", "status":"never", "last_used":""}
  ],
  "stale": [
    {"kind":"mcp", "name":"clawpay", "status":"never", "last_used":""}
  ]
}
```

`stale-tools.tracking-started` (epoch seconds) and `stale-tools.last-alert`
(epoch seconds) are the grace and cooldown timers. Both are plain integer
files written by the alert hook.

---

## Known limitations

- **No plugin-skill visibility.** Skills installed via Claude Code plugins
  (`superpowers:foo`) live outside `~/.claude/skills/` and are not
  enumerated. The audit will not nag you about them; it also cannot help
  you remove them.
- **MCP classification is by name prefix.** `mcp__server__method` →
  `mcp:server`. If two MCP servers share a name, they will be merged.
- **No multi-machine sync.** events.ndjson is local. If you use Claude Code
  on three laptops, each has its own usage history.
- **Hook ordering is not guaranteed.** If another `PostToolUse` hook
  errors before `cleanup-logger.sh` runs, that call goes unrecorded. (In
  practice the logger is short enough that we keep it as the last entry.)
- **The first 30 days are uninformative on purpose.** This is a feature,
  not a bug. Acting on a fresh report would mostly mean archiving things
  you haven't tried yet.

---

## Wiring

`~/.claude/settings.json` has two relevant hook entries:

- `PostToolUse` → `cleanup-logger.sh` (writes events.ndjson)
- `SessionStart` → `stale-tools-alert.sh` (the proactive nudge)

The skill itself is mounted by symlinking the `skill/` directory into the
Claude skills dir:

```bash
ln -sfn ~/code/cleanup/skill ~/.claude/skills/cleanup
```

## Layout

```
cleanup/
├── README.md
├── audit-stale-tools.sh     # report generator
├── cleanup-logger.sh        # PostToolUse logger
├── stale-tools-alert.sh     # SessionStart nudge
├── skill/
│   └── SKILL.md             # /cleanup skill
└── data/                    # gitignored: events, report, timers
```

## Manual use

```bash
bash audit-stale-tools.sh --days 30
cat data/stale-tools.md
```

Or in Claude Code: `/cleanup`.

## Install

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

The first SessionStart writes `data/stale-tools.tracking-started`. After
30 days of grace, new sessions get a one-line `additionalContext` nudge
if any active tool has been untouched. A 7-day cooldown rate-limits the
nudges. Run `/cleanup` in Claude Code anytime to act on the report.

## Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `CLEANUP_EVENTS` | `~/code/cleanup/data/events.ndjson` | Where the logger appends |
| `CLAUDE_AUDIT_DAYS` | `30` | Grace + staleness threshold |
| `CLAUDE_AUDIT_COOLDOWN_DAYS` | `7` | Min days between auto-nudges |

## License

MIT. Built in one evening with Claude Opus 4.7.
