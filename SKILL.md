---
name: johndoe-skill
description: Wafiy's opt-in start-to-PR flow for a new thread - intake (type, name, worktree, commit mode, iteration style), build, then no-mistakes, a green PR, and an Intent rewrite. Use only when the user invokes /johndoe-skill by name; otherwise work normally.
---

# johndoe-skill

The user's own flow for taking one piece of work from a fresh thread to a
CI-green PR. It runs only when invoked by name. Without it, work the default way.

## Hard rule: the user is the only visible author

People reading the PR or the git history must see only the user. This is the
user's explicit instruction and overrides any harness attribution guidance for
the whole flow:

- No `Co-Authored-By` or other agent trailer in any commit message.
- No `Generated with Claude Code` line, robot emoji, or agent mention in the PR
  title or body.
- Commit as the repo's configured git identity; never set an agent name or email.

If the repo squash-merges, a trailer on any branch commit ends up on `main`.
Check before every push: `git log origin/<base>..HEAD --format='%an <%ae>%n%b' | grep -i -E 'co-authored|anthropic|claude'`
must print nothing.

## 1. Intake: one round of questions

Ask everything at once with AskUserQuestion. Skip any question the invocation
arguments already answer (for example `/johndoe-skill with-worktree agent-commit`).

1. **Type:** task, bug-fix, or feature.
2. **Workspace:** `with-worktree` (new isolated worktree) or `not-worktree`
   (current checkout).
3. **Commits:** `agent-commit` (the agent commits) or `user-commit` (the agent
   stages and proposes a message; the user runs `git commit`).
4. **Iteration:** `superpowers`, `bb`, or `plain` (see step 3).

Then get the **name** and the **repo**. Take them from the user's request when it
states them; otherwise ask in one short question. The name is a short kebab-case
slug. If a ticket is mentioned (`ABC-1234`, `PROJ-23`), keep it.

Echo the choices back in one compact block before starting. The user can change
any choice later by saying so.

## 2. Workspace and branch

Branch: `<prefix>/<ticket-lowercase>-<slug>`, or `<prefix>/<slug>` with no ticket,
where the prefix comes from the type (see Commit messages). Match the repo's
convention from `git branch -a --sort=-committerdate | head -20` if it differs.

- **with-worktree:** load the `create-worktree` skill and follow it with this
  branch, based on a freshly fetched default branch. Then move the thread there
  with `update_environment_directory` when that tool exists; otherwise work by
  absolute path.
- **not-worktree:** in the current checkout, run `git status` first and leave
  unrelated uncommitted changes alone. `git fetch`, then create the branch from
  the fresh default branch. Never work directly on the default branch.

## 3. Iteration

- **superpowers:** use `superpowers:brainstorming` for a feature or a vague task,
  `superpowers:systematic-debugging` for a bug-fix, then
  `superpowers:writing-plans` and `superpowers:subagent-driven-development` or
  `superpowers:executing-plans`. Use `superpowers:test-driven-development`
  where the code has tests.
- **bb:** choosing this counts as the user's explicit request to use bb
  orchestration. Split independent parts into child threads with `bb thread spawn`
  into the same environment, wait with `bb thread wait`, and review each child's
  diff before committing. See `bb guide threads`.
- **plain:** work directly without the process skills.

## 4. Commits

At each finished, working slice:

- **agent-commit:** stage only this task's files and commit with the message rules
  below.
- **user-commit:** stage only this task's files, then print the exact message in
  a copyable block, the `git commit` command, and stop. Continue after the user
  says it's committed, and verify with `git log -1`.

### Commit messages

Conventional Commits: `<prefix>(<scope>): <imperative summary>`, lowercase, no
trailing period, under about 72 characters.

| Type | Prefix |
|---|---|
| feature | `feat` |
| bug-fix | `fix` |
| task | the one that fits: `chore`, `refactor`, `docs`, `test`, `perf`, `ci`, `build` |

The scope is the ticket (`ABC-23`) or the area touched (`api/auth`,
`frontend`), following recent `git log --oneline` in the repo. Individual commits
may use a different fitting prefix than the task type, for example a `test` commit
inside a feature. The body explains why in plain prose. Never add a trailer.

## 5. Ship: no-mistakes, then the PR

When the work is complete and committed, run the check from the hard rule, then
load the `no-mistakes` skill and follow it fully. Pass a complete `--intent`, as
that skill requires: its review needs the internal reasoning and the user's
decisions. Escalate `ask-user` findings to the user as that skill says.

Stop driving at `checks-passed`, meaning the PR exists and CI is green. If CI
never gets green, report what blocks it and do not do step 6.

## 6. Correct the PR description

Once CI is green, change only two things in the PR body:

1. **Rewrite the `## Intent` section** so a human teammate can read it as though
   the user wrote it:
   - Keep what changes, why, and the deliberate decisions and ruled-out scope a
     reviewer should know about.
   - Remove agent-voice and process narration: "the user asked/decided", "I
     proposed", "a review finding that says…", pipeline reruns, transient
     failures, notes addressed to the review bot.
   - Write short, plain sentences with bullets where they help. Use the ticket ID
     instead of a PR-number self-reference. A few lines, not a wall of text.
2. **Remove agent attribution** anywhere in the body (the hard rule).

Leave every other section and the `<!-- no-mistakes-pipeline-attestation … -->`
comment exactly as they are.

Write the new Intent text to a file under `$TMPDIR`, then run:

```bash
<skill-dir>/scripts/replace-intent.sh <pr-number-or-url> <intent-file>
```

It swaps only the Intent section body, strips attribution lines, and prints a diff
of the old and new bodies. If the body has no `## Intent` heading, it changes
nothing and says so; tell the user instead of inventing a section.

## 7. Report

State the PR link, CI status, the branch, the no-mistakes fixes (list each one),
and the new Intent text. Then stop: merging is the user's call.
