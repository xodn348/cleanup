#!/bin/bash
# cleanup — proactive stale-tool alert.
# SessionStart hook. Emits hookSpecificOutput.additionalContext only when
#   (a) grace period elapsed since usage tracking began,
#   (b) at least one stale tool exists,
#   (c) cooldown elapsed since the last alert.

set -u

PROJECT_ROOT="/Users/jnnj92/code/cleanup"
DATA_DIR="$PROJECT_ROOT/data"
TRACKING_MARKER="$DATA_DIR/stale-tools.tracking-started"
COOLDOWN_MARKER="$DATA_DIR/stale-tools.last-alert"
THRESHOLD_DAYS="${CLAUDE_AUDIT_DAYS:-30}"
COOLDOWN_DAYS="${CLAUDE_AUDIT_COOLDOWN_DAYS:-7}"

mkdir -p "$DATA_DIR"

if [[ ! -f "$TRACKING_MARKER" ]]; then
  date -u +%s > "$TRACKING_MARKER"
  exit 0
fi

NOW="$(date -u +%s)"
TRACK_START="$(cat "$TRACKING_MARKER" 2>/dev/null || echo "$NOW")"
ELAPSED_DAYS=$(( (NOW - TRACK_START) / 86400 ))
if [[ "$ELAPSED_DAYS" -lt "$THRESHOLD_DAYS" ]]; then
  exit 0
fi

if [[ -f "$COOLDOWN_MARKER" ]]; then
  LAST_ALERT="$(cat "$COOLDOWN_MARKER" 2>/dev/null || echo 0)"
  SINCE_LAST=$(( (NOW - LAST_ALERT) / 86400 ))
  if [[ "$SINCE_LAST" -lt "$COOLDOWN_DAYS" ]]; then
    exit 0
  fi
fi

"$PROJECT_ROOT/audit-stale-tools.sh" --days "$THRESHOLD_DAYS" --quiet >/dev/null 2>&1 || exit 0
OUT_JSON="$DATA_DIR/stale-tools.json"
[[ -f "$OUT_JSON" ]] || exit 0

STALE_COUNT="$(jq '.stale | length' "$OUT_JSON" 2>/dev/null || echo 0)"
[[ "$STALE_COUNT" -gt 0 ]] || exit 0

SUMMARY="$(jq -r --argjson days "$THRESHOLD_DAYS" --arg report "$DATA_DIR/stale-tools.md" '
  "[cleanup] " + (.stale | length | tostring) +
  " tool(s) unused for " + ($days | tostring) + "+ days:\n" +
  (.stale[:10] | map("  - " + .kind + ":" + .name +
    (if .last_used == "" then " (never used)" else " (last: " + .last_used + ")" end)
  ) | join("\n")) +
  (if (.stale | length) > 10 then "\n  - ...and " + ((.stale | length - 10) | tostring) + " more" else "" end) +
  "\n\nFull report: " + $report +
  "\nRecommend the user review and consider removing unused tools via /cleanup (do not auto-delete)."
' "$OUT_JSON")"

echo "$NOW" > "$COOLDOWN_MARKER"

jq -cn --arg ctx "$SUMMARY" \
  '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
