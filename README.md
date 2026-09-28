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

| Dependency | Needed for | How you get it |
|---|---|---|
| `create-worktree` skill | `with-worktree` | bundled in `deps/`, installed by `install.sh` |
| `no-mistakes` CLI and skill | step 3 (required) | `curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh \| sh`, then `no-mistakes init` in any repo |
| `superpowers` plugin | the `superpowers` iteration style (optional) | in Claude Code: `/plugin install superpowers@claude-plugins-official` |
| `gh` CLI, logged in | the PR | [cli.github.com](https://cli.github.com), then `gh auth login` |

If one is missing, the skill says so before it starts: it drops the
`superpowers` option, uses the bundled `create-worktree`, and warns up front
when `no-mistakes` isn't there.

## Install on a new device

1. Clone into your skills folder:

   ```sh
   # bb
   git clone https://github.com/Wapiy-y/johndoe-skill ~/.bb/skills/johndoe-skill

   # Claude Code
   git clone https://github.com/Wapiy-y/johndoe-skill ~/.claude/skills/johndoe-skill
   ```

2. Run the installer. It adds `create-worktree` next to this skill and checks
   the rest, printing the install command for anything missing:

   ```sh
   ~/.bb/skills/johndoe-skill/install.sh
   ```

3. Install whatever it marked ✗, re-run it until everything is ✓, then restart
   your agent session.

To update later: `git -C ~/.bb/skills/johndoe-skill pull`.

## Use

```
/johndoe-skill
/johndoe-skill with-worktree agent-commit
```

Arguments pre-answer intake questions; anything missing is asked once.
