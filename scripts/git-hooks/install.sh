#!/usr/bin/env bash
set -euo pipefail

# Install the repo's git hooks into the active hooks directory, coexisting with
# any git-lfs hooks already there. Run once after cloning:
#   scripts/git-hooks/install.sh

repo_root="$(git rev-parse --show-toplevel)"
src_dir="$repo_root/scripts/git-hooks"

# Honor core.hooksPath if set (this repo points it at .git/hooks); else default.
hooks_dir="$(git config --get core.hooksPath || true)"
hooks_dir="${hooks_dir:-$repo_root/.git/hooks}"
mkdir -p "$hooks_dir"

for hook in pre-commit; do
  target="$hooks_dir/$hook"
  if [[ -e "$target" && ! -L "$target" ]] && ! grep -q "scripts/git-hooks/$hook" "$target" 2>/dev/null; then
    echo "warning: $target exists and is not managed by this installer; leaving it alone" >&2
    continue
  fi
  # Thin delegating wrapper so the tracked script stays the source of truth.
  cat >"$target" <<EOF
#!/usr/bin/env bash
exec "\$(git rev-parse --show-toplevel)/scripts/git-hooks/$hook" "\$@"
EOF
  chmod +x "$target"
  echo "installed: $target -> scripts/git-hooks/$hook"
done
