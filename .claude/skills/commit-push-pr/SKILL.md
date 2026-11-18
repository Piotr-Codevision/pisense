---
name: commit-push-pr
description: Commit the current changes on a feature branch, push it to GitHub and open a pull request (or add to the open one). Only when the user invokes it.
argument-hint: "[branch-name] [description of the change]"
disable-model-invocation: true
allowed-tools: Bash(scripts/git-flow.sh *) Bash(scripts/dev.sh *) Bash(git status *) Bash(git diff *)
---

# Commit, push and open a pull request

Arguments: `$ARGUMENTS` (both optional). If the first word looks like a branch name
(contains `/`, no spaces), it is the branch; the rest describes the change and is the main
input for the texts below.

1. Run `git status --short` and `git diff --stat`. If source, build or script files
   changed and `/build-verify` has not passed since the last change, run
   `scripts/dev.sh build-verify` and stop on `RESULT: FAIL`.
2. Write two files outside the repository (your scratchpad, or `mktemp`):
   - **Commit message:** subject `Prefix: Description` (e.g. `Build:`, `Chore:`, `Docs:`,
     `Fix:`; at most 72 characters), a blank line, short bullets, then the attribution
     lines your session requires for commits.
   - **PR body:** `## Summary` (what and why), `## Test plan` (checklist of what was
     actually run; never claim unexecuted checks), then the attribution line your session
     requires for pull requests.
   - Never include personal or machine-specific data: home or scratchpad paths, IP
     addresses, host names, user names, e-mail addresses, credentials, keys or tokens.
3. Run once:
   `scripts/git-flow.sh pr [--branch <name>] [--add <new file>]... --message-file <file> --body-file <file>`
   - Pass every new untracked file that belongs to the change with `--add`.
   - On the default branch a branch is created (`--branch`, or derived from the subject);
     on a feature branch the commit goes there and an open PR is reused.
4. Report the commit, branch and PR link from the output.
   - `[WARN]` lines: tell the user which files were not committed.
   - `RESULT: FAIL (sensitive-data)`: show the listed locations, fix the content if it is
     yours to fix, and never pass `--allow-sensitive` without the user's explicit approval.
   - Any other failure: show it and stop.
