#!/usr/bin/env bash
# Copy gitignored local files (env, toml, local config) from a repo's main
# checkout into one of its worktrees. Never overwrites a file that exists.
#
# Usage: sync-local-files.sh [--from <main-checkout>] [--dry-run]
#                            [--include <glob>]... [<worktree-dir>]
#
# <worktree-dir> defaults to the current directory. The source defaults to the
# repo's main worktree (first entry of `git worktree list`).
#
# Files are picked in two passes:
#   1. .worktreeinclude (gitignore syntax) in the main checkout, if present.
#   2. Heuristic: every gitignored file whose name looks like env/config,
#      skipping dependency and build directories.
# Other gitignored files are listed at the end but not copied.

set -euo pipefail

src="" dest="" dry_run=0
extra_globs=()

while [ $# -gt 0 ]; do
  case "$1" in
    --from) src="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --include) extra_globs+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) dest="$1"; shift ;;
  esac
done

dest="$(cd "${dest:-.}" && git rev-parse --show-toplevel)"
if [ -z "$src" ]; then
  src="$(git -C "$dest" worktree list --porcelain | sed -n '1s/^worktree //p')"
fi
src="$(cd "$src" && git rev-parse --show-toplevel)"

if [ "$src" = "$dest" ]; then
  echo "source and destination are the same checkout ($src); pass the worktree path or --from" >&2
  exit 2
fi

# Directories never worth copying from or searching.
is_skipped_dir() {
  case "/$1/" in
    */node_modules/*|*/.git/*|*/.venv/*|*/venv/*|*/__pycache__/*|*/.pytest_cache/*|\
    */.mypy_cache/*|*/.ruff_cache/*|*/dist/*|*/build/*|*/out/*|*/target/*|*/vendor/*|\
    */.next/*|*/.nuxt/*|*/.turbo/*|*/.cache/*|*/coverage/*|*/.gradle/*|*/.terraform/*|\
    */.claude/*|*/.superpowers/*|*/.tanstack/*|*/.idea/*|*/tmp/*|*/logs/*|*/.worktrees/*)
      return 0 ;;
  esac
  return 1
}

# Does this basename look like env or local config?
is_config_name() {
  local name lower g
  name="$1"
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.example|*.sample|*.template|*.dist|*.bak|*.orig|*.log) return 1 ;;
  esac
  case "$lower" in
    .env|.env.*|*.env|.envrc|.dev.vars|\
    *.toml|\
    config.*|*.config.local.*|*.local|*.local.*|*-local.*|*_local.*|\
    settings.*|secrets.*|.secrets|local.settings.json|\
    application*.yml|application*.yaml|application*.properties|\
    .npmrc|.yarnrc.yml|.tool-versions)
      return 0 ;;
  esac
  if [ ${#extra_globs[@]} -gt 0 ]; then
    for g in "${extra_globs[@]}"; do
      # shellcheck disable=SC2254
      case "$name" in $g) return 0 ;; esac
    done
  fi
  return 1
}

# Is this directory a config folder (config/, conf/, secrets/, env/, ...)?
is_config_dir() {
  case "/$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')/" in
    */config/*|*/configs/*|*/conf/*|*/settings/*|*/secrets/*|*/env/*|*/.vscode/*) return 0 ;;
  esac
  return 1
}

picked="$(mktemp)" others="$(mktemp)"
trap 'rm -f "$picked" "$others"' EXIT

# Pass 1: .worktreeinclude — untracked files matching its patterns.
if [ -f "$src/.worktreeinclude" ]; then
  git -C "$src" ls-files --others --ignored --exclude-from=.worktreeinclude \
    | while IFS= read -r f; do is_skipped_dir "$(dirname "$f")" || echo "$f"; done >> "$picked"
fi

# Pass 2: heuristic over all gitignored paths (ignored dirs arrive collapsed).
git -C "$src" ls-files --others --ignored --exclude-standard --directory \
  | while IFS= read -r entry; do
      case "$entry" in
        */)
          dir="${entry%/}"
          is_skipped_dir "$dir" && continue
          (cd "$src" && find "$dir" -type f 2>/dev/null) | while IFS= read -r f; do
            is_skipped_dir "$(dirname "$f")" && continue
            if is_config_name "$(basename "$f")" || is_config_dir "$(dirname "$f")"; then
              echo "$f" >> "$picked"
            else
              echo "$f" >> "$others"
            fi
          done
          ;;
        *)
          is_skipped_dir "$(dirname "$entry")" && continue
          case "$(basename "$entry")" in .DS_Store) continue ;; esac
          if is_config_name "$(basename "$entry")" || is_config_dir "$(dirname "$entry")"; then
            echo "$entry" >> "$picked"
          else
            echo "$entry" >> "$others"
          fi
          ;;
      esac
    done

copied=0 existing=0
echo "source:      $src"
echo "destination: $dest"
[ $dry_run -eq 1 ] && echo "(dry run: nothing is written)"
echo

while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ -e "$dest/$rel" ]; then
    echo "exists   $rel"; existing=$((existing + 1)); continue
  fi
  if [ $dry_run -eq 0 ]; then
    mkdir -p "$dest/$(dirname "$rel")"
    cp -p "$src/$rel" "$dest/$rel"
  fi
  if [ $dry_run -eq 1 ]; then echo "would copy $rel"; else echo "copied   $rel"; fi
  copied=$((copied + 1))
done < <(sort -u "$picked")

echo
[ $dry_run -eq 1 ] && verb="to copy" || verb="copied"
echo "$copied $verb, $existing already present"

if [ -s "$others" ]; then
  sort -u "$others" | grep -vxF -f <(sort -u "$picked") > "$others.left" || true
  if [ -s "$others.left" ]; then
    echo
    echo "Other gitignored files in the source, not copied (copy by hand or pass --include):"
    head -n 30 "$others.left" | sed 's/^/  /'
    n="$(wc -l < "$others.left" | tr -d ' ')"
    [ "$n" -gt 30 ] && echo "  ... and $((n - 30)) more"
  fi
  rm -f "$others.left"
fi
