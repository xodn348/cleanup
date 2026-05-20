#!/bin/bash
# cleanup — stale tool auditor.
# Reads Claude Code tool-usage events (kind=post_tool) from a JSONL bus,
# enumerates currently active MCPs and user skills, and writes a report
# of which have not been used recently. Never deletes anything.
#
# Outputs:
#   data/stale-tools.json — full inventory + stale list
#   data/stale-tools.md   — human-readable summary
# Exit code is always 0; consumers read the files.
#
# Usage: audit-stale-tools.sh [--days N] [--quiet]

set -u

DAYS=30
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) shift ;;
  esac
done

PROJECT_ROOT="/Users/jnnj92/code/cleanup"
# The Claude Code event bus is provided by cleanup-logger.sh.
# That hook (cleanup-logger.sh on PostToolUse) appends one ndjson line per
# tool call with {kind:"post_tool", tool, skill?}.
EVENTS="${CLEANUP_EVENTS:-$PROJECT_ROOT/data/events.ndjson}"
OUT_JSON="$PROJECT_ROOT/data/stale-tools.json"
OUT_MD="$PROJECT_ROOT/data/stale-tools.md"
mkdir -p "$PROJECT_ROOT/data"

NOW_EPOCH="$(date -u +%s)"
CUTOFF_EPOCH="$(( NOW_EPOCH - DAYS * 86400 ))"
CUTOFF_ISO="$(date -u -r "$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
              date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

USAGE_TMP="$(mktemp)"
MCP_TMP="$(mktemp)"
SKILLS_TMP="$(mktemp)"
ENTRIES_TMP="$(mktemp)"
trap 'rm -f "$USAGE_TMP" "$MCP_TMP" "$SKILLS_TMP" "$ENTRIES_TMP"' EXIT

# 1. Build usage map from events.ndjson.
if [[ -f "$EVENTS" ]]; then
  jq -r 'select(.kind=="post_tool" and (.tool // "") != "") |
         if (.tool | startswith("mcp__")) then
           [ "mcp:" + ((.tool | split("__"))[1] // ""), .ts ]
         elif (.tool == "Skill" and (.skill // "") != "") then
           [ "skill:" + .skill, .ts ]
         else empty end |
         @tsv' "$EVENTS" 2>/dev/null \
    | sort -k1,1 -k2,2 \
    | awk -F'\t' '{m[$1]=$2} END{for (k in m) printf "%s\t%s\n", k, m[k]}' \
    > "$USAGE_TMP"
fi

usage_for() {
  awk -F'\t' -v k="$1" '$1==k {print $2; exit}' "$USAGE_TMP"
}

# 2. Enumerate active MCP servers via `claude mcp list`.
claude mcp list 2>/dev/null \
  | grep -E '^[A-Za-z0-9_.-][^:]*:' \
  | sed 's/:.*//' \
  | sed 's/[[:space:]]*$//' \
  | sed 's/ /_/g' \
  > "$MCP_TMP" || true

# 3. Enumerate user skills in ~/.claude/skills/ (must contain SKILL.md).
if [[ -d "$HOME/.claude/skills" ]]; then
  for d in "$HOME/.claude/skills"/*/; do
    [[ -f "$d/SKILL.md" ]] || continue
    basename "$d" >> "$SKILLS_TMP"
  done
fi

# 4. Classify each active item.
build_entries() {
  local kind="$1" listfile="$2" prefix="$3"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local last status
    last="$(usage_for "${prefix}${name}")"
    if   [[ -z "$last"   ]]; then status="never"
    elif [[ "$last" < "$CUTOFF_ISO" ]]; then status="stale"
    else status="used"
    fi
    jq -cn --arg kind "$kind" --arg name "$name" --arg last "$last" --arg status "$status" \
      '{kind:$kind, name:$name, last_used:$last, status:$status}'
  done < "$listfile"
}
build_entries "mcp"   "$MCP_TMP"    "mcp:"   >> "$ENTRIES_TMP"
build_entries "skill" "$SKILLS_TMP" "skill:" >> "$ENTRIES_TMP"

# 5. Write outputs.
jq -cn \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson days "$DAYS" \
  --arg cutoff "$CUTOFF_ISO" \
  --slurpfile entries <(jq -s '.' "$ENTRIES_TMP") \
  '{generated_at:$generated_at, threshold_days:$days, cutoff:$cutoff,
    entries:$entries[0],
    stale: ($entries[0] | map(select(.status=="stale" or .status=="never")))}' \
  > "$OUT_JSON"

STALE_COUNT="$(jq '.stale | length' "$OUT_JSON")"
TOTAL_COUNT="$(jq '.entries | length' "$OUT_JSON")"

{
  echo "# Stale tool audit"
  echo
  echo "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Threshold: ${DAYS} days (cutoff: ${CUTOFF_ISO})"
  echo "- Stale: ${STALE_COUNT} / ${TOTAL_COUNT}"
  echo
  echo "## Stale (recommend review)"
  echo
  if [[ "$STALE_COUNT" -eq 0 ]]; then
    echo "_None — every active tool was used within the last ${DAYS} days._"
  else
    printf "| Kind | Name | Last used |\n|---|---|---|\n"
    jq -r '.stale[] | "| \(.kind) | \(.name) | \(if .last_used == "" then "never" else .last_used end) |"' "$OUT_JSON"
  fi
  echo
  echo "## All active tools"
  echo
  printf "| Kind | Name | Status | Last used |\n|---|---|---|---|\n"
  jq -r '.entries[] | "| \(.kind) | \(.name) | \(.status) | \(if .last_used == "" then "—" else .last_used end) |"' "$OUT_JSON"
} > "$OUT_MD"

if [[ "$QUIET" -ne 1 ]]; then
  echo "Stale: ${STALE_COUNT} / ${TOTAL_COUNT}  →  $OUT_MD"
fi
