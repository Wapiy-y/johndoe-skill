#!/usr/bin/env bash
# Report what would be lost by deleting a git worktree. Read-only.
#
# Usage: worktree-status.sh <worktree-dir-or-branch> [--repo <any-checkout>]
#
# Prints the worktree's branch, uncommitted files, commits not on the remote,
# stashes, the branch's PR state (if gh is installed), processes running
# inside it, and whether bb manages it. The last line is a verdict:
#   VERDICT: CLEAN   nothing would be lost
#   VERDICT: CHECK   something needs the user's decision first
#   VERDICT: STALE   registered with git but the folder is gone (prune it)
#   VERDICT: MAIN    this is the main checkout; never delete it

set -uo pipefail

target="" repo="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) target="$1"; shift ;;
  esac
done
[ -z "$target" ] && { echo "usage: worktree-status.sh <worktree-dir-or-branch> [--repo <checkout>]" >&2; exit 2; }

# A path that exists is used to find the repo; otherwise treat target as a branch.
[ -d "$target" ] && repo="$target"
repo_top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "not inside a git repo: $repo (pass --repo)" >&2; exit 2; }

# Find the worktree entry: match by path first, then by branch.
wt="" branch="" main=""
abs_target="$(cd "$target" 2>/dev/null && pwd -P || echo "$target")"
while IFS= read -r line; do
  case "$line" in
    "worktree "*) cur="${line#worktree }"; [ -z "$main" ] && main="$cur" ;;
    "branch "*)
      b="${line#branch refs/heads/}"
      cur_real="$(cd "$cur" 2>/dev/null && pwd -P || echo "$cur")"
      if [ "$cur_real" = "$abs_target" ] || [ "$cur" = "$target" ] || [ "$b" = "$target" ]; then
        wt="$cur"; branch="$b"
      fi ;;
    detached)
      cur_real="$(cd "$cur" 2>/dev/null && pwd -P || echo "$cur")"
      [ "$cur_real" = "$abs_target" ] && { wt="$cur"; branch="(detached)"; } ;;
  esac
done < <(git -C "$repo_top" worktree list --porcelain)

[ -z "$wt" ] && { echo "no worktree matches '$target'. Known worktrees:"; git -C "$repo_top" worktree list; exit 2; }

echo "worktree: $wt"
echo "branch:   $branch"
echo "main:     $main"

if [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$(cd "$main" && pwd -P)" ]; then
  echo; echo "VERDICT: MAIN"; exit 0
fi
if [ ! -d "$wt" ]; then
  echo; echo "Folder is gone; git still lists it. Run: git -C \"$main\" worktree prune"
  echo "VERDICT: STALE"; exit 0
fi

concerns=0

echo; echo "== Uncommitted changes (tracked + untracked, excluding gitignored)"
changes="$(git -C "$wt" status --porcelain)"
if [ -n "$changes" ]; then
  echo "$changes" | head -n 20
  n="$(echo "$changes" | wc -l | tr -d ' ')"; [ "$n" -gt 20 ] && echo "... and $((n - 20)) more"
  concerns=1
else
  echo "none"
fi

echo; echo "== Commits not on the remote"
if [ "$branch" = "(detached)" ]; then
  echo "detached HEAD at $(git -C "$wt" log -1 --oneline)"
  concerns=1
elif upstream="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  ahead="$(git -C "$wt" log --oneline "@{u}..HEAD")"
  if [ -n "$ahead" ]; then echo "$ahead" | head -n 20; echo "(ahead of $upstream)"; concerns=1
  else echo "none (in sync with $upstream)"; fi
else
  base="$(git -C "$wt" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  ahead="$(git -C "$wt" log --oneline "$base..HEAD" 2>/dev/null)"
  if [ -n "$ahead" ]; then
    echo "$ahead" | head -n 20
    echo "(branch was never pushed; these commits exist only locally, relative to $base)"
    concerns=1
  else
    echo "none (no upstream, and nothing beyond $base)"
  fi
fi

echo; echo "== Stashes made on this branch"
stashes="$(git -C "$wt" stash list | grep -F "on $branch:" || true)"
if [ -n "$stashes" ]; then echo "$stashes"; echo "(stashes survive worktree removal, but are easy to forget)"
else echo "none"; fi

echo; echo "== Pull request"
if [ "$branch" != "(detached)" ] && command -v gh >/dev/null 2>&1; then
  pr="$(cd "$wt" && gh pr list --head "$branch" --state all --limit 1 \
        --json number,state,url --template '{{range .}}#{{.number}} {{.state}} {{.url}}{{end}}' 2>/dev/null)" \
    || pr="(gh failed: not authenticated or no network)"
  echo "${pr:-no PR for this branch}"
else
  echo "skipped (gh not installed or detached HEAD)"
fi

echo; echo "== Processes running inside the worktree"
procs="$(lsof -d cwd -Fpcn 2>/dev/null | awk -v root="$(cd "$wt" && pwd -P)" '
  /^p/ { pid = substr($0, 2) } /^c/ { cmd = substr($0, 2) }
  /^n/ { p = substr($0, 2); if (p == root || index(p, root "/") == 1) print pid "  " cmd "  " p }')"
if [ -n "$procs" ]; then echo "$procs"; concerns=1; else echo "none"; fi

echo; echo "== bb environment"
if command -v bb >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  real="$(cd "$wt" && pwd -P)"
  env="$(bb environment list --json 2>/dev/null | jq -r --arg p "$wt" --arg r "$real" \
        '.[]? | select(.path == $p or .path == $r) | "\(.id)  \(.status)  \(.environmentProviderId)"')"
  if [ -n "$env" ]; then echo "$env"; bb_env_id="${env%% *}"
  else echo "not managed by bb"; fi
else
  echo "skipped (bb or jq not installed)"
fi

echo
if [ -n "${bb_env_id:-}" ]; then
  echo "DELETE WITH: bb environment delete $bb_env_id"
else
  echo "DELETE WITH: git -C \"$main\" worktree remove \"$wt\""
fi
if [ $concerns -eq 0 ]; then echo "VERDICT: CLEAN"; else echo "VERDICT: CHECK"; fi
