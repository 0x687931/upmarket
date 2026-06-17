#!/usr/bin/env bash
# SessionStart guard: surface per-worktree build/ cache growth so disk erosion
# is never silent. Each worktree builds into its own repo-local build/DerivedData
# (2–10 GB); merged-but-unpruned worktrees pile these up unnoticed. If the total
# across all worktrees crosses the threshold, warn with the prune command.
# Stays silent (no output) when under threshold.

THRESHOLD_GB="${UPMARKET_BUILD_CACHE_THRESHOLD_GB:-8}"

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

total_kb=0
list=""
while IFS= read -r wt; do
  b="$wt/build"
  [ -d "$b" ] || continue
  kb=$(du -sk "$b" 2>/dev/null | cut -f1)
  [ -z "$kb" ] && continue
  total_kb=$((total_kb + kb))
  list+="$kb|$b"$'\n'
done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

# Quiet unless the total build cache exceeds the threshold.
[ "$total_kb" -le $((THRESHOLD_GB * 1048576)) ] && exit 0

report=$(printf '%s' "$list" | awk -F'|' 'NF==2{printf "  %6.2f GB  %s\n", $1/1048576, $2}' | sort -rh)
total_gb=$(awk "BEGIN{printf \"%.1f\", $total_kb/1048576}")

msg="⚠️  Upmarket build caches total ${total_gb} GB across worktrees (threshold ${THRESHOLD_GB} GB).
${report}
build/ is regenerable. Prune merged worktrees to reclaim it:
  git worktree list                 # find stale ones
  git worktree remove <path>        # removes the worktree and its build/
…or just delete a build/ dir directly. CI is unaffected (it pins its own DerivedData)."

python3 -c 'import json,sys; print(json.dumps({"systemMessage": sys.argv[1]}))' "$msg"
exit 0
