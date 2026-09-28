#!/usr/bin/env bash
# Replace only the "## Intent" section of a PR body and strip agent attribution.
#
#   replace-intent.sh <pr-number-or-url> <intent-file> [--dry-run]
#   replace-intent.sh --body-file <body.md> <intent-file>   # offline, prints result
#
# Every other section and the no-mistakes attestation comment stay byte-identical.
set -euo pipefail

usage() { sed -n 2,7p "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage

offline_body="" pr="" dry_run=0
if [ "$1" = "--body-file" ]; then
  offline_body="$2"; shift 2
else
  pr="$1"; shift
fi
intent_file="${1:?intent file required}"; shift
[ "${1:-}" = "--dry-run" ] && dry_run=1
[ -s "$intent_file" ] || { echo "error: intent file is empty or missing: $intent_file" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/replace-intent.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [ -n "$offline_body" ]; then
  cp "$offline_body" "$work/old.md"
else
  gh pr view "$pr" --json body --jq .body > "$work/old.md"
fi

python3 - "$work/old.md" "$intent_file" "$work/new.md" <<'PY'
import re, sys
old_path, intent_path, new_path = sys.argv[1:]
body = open(old_path, encoding="utf-8").read()
intent = open(intent_path, encoding="utf-8").read().strip("\n")

m = re.search(r"(?im)^##[ \t]+intent[ \t]*$", body)
if not m:
    sys.stderr.write("no '## Intent' heading in this PR body; nothing changed\n")
    sys.exit(3)

# The section ends at the next heading of level 1-2, the attestation comment, or EOF.
rest = body[m.end():]
end = re.search(r"(?m)^(#{1,2}[ \t]|<!-- no-mistakes-pipeline-attestation)", rest)
tail = rest[end.start():] if end else ""
new = body[:m.end()] + "\n\n" + intent + "\n\n" + tail.lstrip("\n")

# Strip agent attribution lines anywhere in the body.
attribution = re.compile(
    r"(?im)^[ \t]*(?:🤖[^\n]*|[^\n]*generated with \[?claude code[^\n]*|co-authored-by:[^\n]*)\n?")
new = attribution.sub("", new)
new = re.sub(r"\n{3,}", "\n\n", new).rstrip("\n") + "\n"
open(new_path, "w", encoding="utf-8").write(new)
PY

diff -u --label old --label new "$work/old.md" "$work/new.md" || true

if [ -n "$offline_body" ]; then
  echo "--- offline mode: result below, nothing uploaded ---"
  cat "$work/new.md"
elif [ "$dry_run" = 1 ]; then
  echo "--- dry run: PR not edited ---"
else
  gh pr edit "$pr" --body-file "$work/new.md" >/dev/null
  echo "PR $pr body updated"
fi
