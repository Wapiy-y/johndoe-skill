# johndoe-skill

An opt-in start-to-PR flow for coding agents (Claude Code, bb). Invoke it by
name at the start of a thread and it runs:

1. **Intake:** one round of questions: type (task, bug-fix, feature), name,
   worktree or current checkout, who commits, and iteration style.
2. **Build:** the work itself, on a fresh branch.
3. **Ship:** the `no-mistakes` pipeline, stopping once the PR exists and CI is
   green.
4. **Intent rewrite:** `scripts/replace-intent.sh` rewrites the PR's Intent
   section in plain human voice.

Commits and PRs carry no agent trailers or "Generated with" lines.

## Depends on

- `no-mistakes` skill (required, for step 3)
- `create-worktree` skill (for `with-worktree`)
- `superpowers` skills (for the `superpowers` iteration style)
- `gh` CLI, logged in

## Install

Clone into a skills directory and restart your agent session:

```sh
# bb
git clone https://github.com/Wapiy-y/johndoe-skill ~/.bb/skills/johndoe-skill

# Claude Code
git clone https://github.com/Wapiy-y/johndoe-skill ~/.claude/skills/johndoe-skill
```

## Use

```
/johndoe-skill
/johndoe-skill with-worktree agent-commit
```

Arguments pre-answer intake questions; anything missing is asked once.
