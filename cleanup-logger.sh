#!/bin/bash
# cleanup — PostToolUse logger.
# Reads hook event JSON on stdin, appends one ndjson line per tool call to
# data/events.ndjson. This is the data source audit-stale-tools.sh consumes.

set -u
EVENTS="${CLEANUP_EVENTS:-/Users/jnnj92/code/cleanup/data/events.ndjson}"
mkdir -p "$(dirname "$EVENTS")"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
INPUT="$(cat 2>/dev/null || echo '{}')"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)"
[[ -z "$TOOL" ]] && exit 0

SKILL=""
if [[ "$TOOL" == "Skill" ]]; then
  SKILL="$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)"
fi

jq -cn --arg ts "$TS" --arg tool "$TOOL" --arg skill "$SKILL" \
  '{ts:$ts, kind:"post_tool", tool:$tool, skill:$skill}' \
  >> "$EVENTS" 2>/dev/null

exit 0
