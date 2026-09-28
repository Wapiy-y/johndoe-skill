#!/usr/bin/env bash
# Install the create-worktree skill bundled in deps/, then check the
# dependencies that have to be installed separately.
#
#   ./install.sh [skills-dir]   default: the folder this repo was cloned into
#
# Clone this repo into your skills folder first, for example
# ~/.bb/skills/johndoe-skill or ~/.claude/skills/johndoe-skill. Safe to re-run:
# an existing create-worktree skill is never overwritten.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:-$(dirname "$here")}"
missing=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
miss() { printf '  \033[31m✗\033[0m %s\n      %s\n' "$1" "$2"; missing=1; }

echo "Skills folder: $dest"
mkdir -p "$dest"

if [ -e "$dest/create-worktree" ]; then
  ok "create-worktree (already installed, left alone)"
else
  cp -R "$here/deps/create-worktree" "$dest/create-worktree"
  ok "create-worktree (installed to $dest/create-worktree)"
fi

echo "Dependencies:"

if command -v no-mistakes >/dev/null 2>&1; then
  ok "no-mistakes CLI ($(no-mistakes --version 2>/dev/null | head -1 | awk '{print $3}'))"
else
  miss "no-mistakes CLI (required to ship)" \
    "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh"
fi

if [ -e "$HOME/.claude/skills/no-mistakes/SKILL.md" ] || [ -e "$HOME/.agents/skills/no-mistakes/SKILL.md" ]; then
  ok "no-mistakes skill"
else
  miss "no-mistakes skill" "run 'no-mistakes init' inside any git repo"
fi

if grep -qs '"superpowers@' "$HOME/.claude/plugins/installed_plugins.json"; then
  ok "superpowers plugin"
else
  miss "superpowers plugin (optional; without it the flow uses plain iteration)" \
    "in Claude Code: /plugin install superpowers@claude-plugins-official"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  ok "gh CLI, logged in"
else
  miss "gh CLI, logged in" "install gh (https://cli.github.com), then: gh auth login"
fi

echo
if [ "$missing" -eq 0 ]; then
  echo "All set. Restart your agent session, then run /johndoe-skill."
else
  echo "Install the items marked ✗, re-run ./install.sh, then restart your agent session."
fi
