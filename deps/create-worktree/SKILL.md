---
name: create-worktree
description: Use when creating, deleting, or cleaning up git worktrees in any repo, or when a worktree is missing its gitignored local files (.env, *.toml, config.local.*) and services won't start. Copies those files from the main checkout on create; checks for unsaved work before delete.
---

# Create and delete worktrees

A fresh `git worktree add` only contains tracked files. The files a developer
needs to run anything — `.env`, `config.toml`, `*.local.*`, and so on — are
gitignored, so they stay behind in the main checkout. bb's `.worktreeinclude`
copy is meant to cover this, but it does not fire when the bb project root is a
wrapper folder rather than the repo itself, or when the worktree was made by
hand. `scripts/sync-local-files.sh` does the copy for any repo.

## Creating a new worktree

1. **Find the repo.** Resolve the main checkout with
   `git -C <path> worktree list --porcelain` (the first `worktree` line). If the
   user's folder holds several repos, ask which one only when the request
   doesn't say.

2. **Pick the location.** Follow what the repo already does: look at existing
   entries in `git worktree list` and for a sibling `<repo>.worktrees/` or an
   in-repo `.worktrees/` directory. If there's no convention, use
   `<parent-of-repo>/<repo-name>.worktrees/<name>`.

3. **Pick the branch.** Use the name the user gave. Otherwise match the repo's
   convention from `git branch -a --sort=-committerdate | head -20` (for
   example `fix/abc-1234-short-desc`), and ask for a ticket number only if the
   convention needs one and the user didn't give it. Base it on the default
   branch (`git symbolic-ref --short refs/remotes/origin/HEAD`), or on the base
   the user named. Run `git fetch origin <base>` first so the base is current.

4. **Create it:**

   ```bash
   git -C <main-checkout> worktree add <worktree-path> -b <branch> origin/<base>
   ```

   If the branch already exists, drop `-b` and check it out instead.

5. **Copy the local files:**

   ```bash
   <skill-dir>/scripts/sync-local-files.sh <worktree-path>
   ```

   Existing files are never overwritten. Add `--dry-run` to preview, `--from
   <checkout>` to copy from somewhere other than the main checkout, and
   `--include '<glob>'` (repeatable) for file names the heuristic misses.

6. **Check the output.** It lists what was copied, what already existed, and
   other gitignored files that were left behind (certs, local scripts, data).
   If any of those look like something the app needs to run, copy them with
   `--include` and tell the user which ones you added. If nothing was
   copied, say so plainly — the repo may simply have no local config.

7. **Report** the worktree path, branch, base, and the copied files.

## Repairing an existing worktree

Run step 5 from inside the worktree (or pass its path) and go on to step 6.
Use this when a service in a worktree fails on a missing config or env file.

## Deleting a worktree

Deleting is hard to undo: uncommitted work and never-pushed commits in the
worktree are gone once it's removed. Always confirm with the user before the
delete runs, even when the check comes back clean.

1. **Check it:**

   ```bash
   <skill-dir>/scripts/worktree-status.sh <worktree-path-or-branch> [--repo <checkout>]
   ```

   Read-only. It reports uncommitted files, commits not on the remote, stashes,
   the branch's PR state, processes running inside the worktree, and whether
   bb manages it, then prints the exact `DELETE WITH:` command and a verdict.
   For several worktrees ("clean up merged worktrees"), run it on each entry
   in `git worktree list` and present the results as one table.

2. **Act on the verdict:**
   - `MAIN` — the main checkout. Refuse; never delete it.
   - `STALE` — the folder is already gone. Run `git worktree prune`; nothing
     else is lost.
   - `CLEAN` — show the user the one-line summary and ask to confirm.
   - `CHECK` — show exactly what would be lost (the files, the commits, the
     running processes) and ask what to do: commit and push first, stop the
     processes, or delete anyway.

3. **Delete** with the `DELETE WITH:` command the script printed:
   - bb-managed worktree: `bb environment delete <id>`. bb refuses while a
     thread is still running in it — ask the user to archive those threads
     (`bb environment archive-threads <id>`) rather than forcing it.
   - Plain worktree: `git worktree remove <path>`. Git refuses when there are
     uncommitted or untracked files; add `--force` only after the user
     explicitly said to discard them. Gitignored files (the copied `.env`,
     `config.toml`) are deleted without warning — they're copies of the main
     checkout's files unless the user edited them in the worktree.

4. **The branch** stays after the worktree goes. Ask whether to delete it too:
   - `git branch -d <branch>` works when git sees it merged.
   - Squash-merge repos never look merged to git, so `-d` fails. Use `-D` only
     when the PR shows `MERGED` or the user says so.
   - Delete the remote branch (`git push origin --delete <branch>`) only on an
     explicit request.

5. **Report** what was removed: worktree path, and the branch if deleted.

## What the script picks

1. Paths matched by `.worktreeinclude` (gitignore syntax) in the main checkout,
   when that file exists.
2. Any gitignored file named like env or config: `.env`, `.env.*`, `*.env`,
   `.envrc`, `.dev.vars`, `*.toml`, `config.*`, `*.local`, `*.local.*`,
   `*-local.*`, `*_local.*`, `settings.*`, `secrets.*`,
   `application*.{yml,yaml,properties}`, `.npmrc`, `.yarnrc.yml`,
   `.tool-versions`.

It skips `*.example`/`*.sample`/`*.template` and dependency, build, cache, and
agent folders (`node_modules`, `.venv`, `dist`, `build`, `target`, `vendor`,
`.next`, `.claude`, …).

## Boundaries

- These files often hold secrets. Copy them only between checkouts on this
  machine; never print their contents, commit them, or paste them anywhere.
- Don't install dependencies, run migrations, or start services unless the
  user asks — the task ends at a worktree with its config in place.
