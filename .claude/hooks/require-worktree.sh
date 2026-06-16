#!/usr/bin/env bash
# PreToolUse guard: edits and destructive git/file ops must happen inside a
# dedicated worktree on a feature branch — never the primary checkout or main.
# Blocks (exit 2) with a message telling the agent to create a worktree first.
#
# Rationale: concurrent agents share this repo's working tree. Editing the
# primary checkout corrupts other agents' uncommitted work. See CLAUDE.md
# "Workflow" and ~/.claude/WORKTREE_WORKFLOW.md.

input=$(cat)

field() { # $1 = python expression on `d` (the parsed input dict)
  printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null
}

tool=$(field 'd.get("tool_name","")')

block() { printf '%s\n' "$1" >&2; exit 2; }

# Allow unless the target sits in the primary checkout or on main/master.
guard_dir() {
  local dir="$1" gitdir branch
  # Walk up to an existing directory (new files: parent may not exist yet).
  while [ -n "$dir" ] && [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    dir=$(dirname "$dir")
  done
  gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || return 0  # not a git repo: allow
  case "$gitdir" in
    */worktrees/*) ;;  # linked worktree — good
    *) block "BLOCKED — not in a worktree. '$dir' is the primary checkout, which other agents share. Create a dedicated worktree on a feature branch first:
  git worktree add ../upmarket-<task> -b <branch>
then operate on files under that path. (CLAUDE.md: never edit/commit in the primary checkout.)" ;;
  esac
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  case "$branch" in
    main|master) block "BLOCKED — worktree HEAD is on '$branch'. Switch the worktree to a feature branch before editing/deleting." ;;
  esac
}

case "$tool" in
  Edit|Write|NotebookEdit)
    file=$(field 'd.get("tool_input",{}).get("file_path") or d.get("tool_input",{}).get("notebook_path") or ""')
    [ -z "$file" ] && exit 0
    guard_dir "$(dirname "$file")"
    ;;
  Bash)
    cmd=$(field 'd.get("tool_input",{}).get("command","")')
    # Only guard clearly destructive / history-mutating commands.
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]| )(rm|rmdir|mv)([[:space:]]|$)|git[[:space:]]+(rm|mv|commit|reset|restore|checkout|switch|clean|stash|rebase|merge|cherry-pick|am)([[:space:]]|$)'; then
      # Resolve the dir the command acts on: honour `git -C <dir>` and a leading `cd <dir>`.
      target=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
      [ -z "$target" ] && target=$(printf '%s' "$cmd" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&|;]+).*/\1/p' | head -1)
      [ -z "$target" ] && target="$PWD"
      guard_dir "$target"
    fi
    ;;
esac
exit 0
