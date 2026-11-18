---
name: pr-merged
description: After a pull request was merged on GitHub - update the local default branch and delete the merged feature branch locally and remotely. Only when the user invokes it.
argument-hint: "[branch-name]"
disable-model-invocation: true
allowed-tools: Bash(scripts/git-flow.sh *)
---

# Sync after a merged pull request

Make exactly one Bash call, exactly as written (no `cd` prefix):

```sh
scripts/git-flow.sh merged $ARGUMENTS
```

- Without an argument it deletes the branch that is currently checked out (if it is not
  the default branch).
- Report the step lines and the final `RESULT:` line. On `RESULT: FAIL`, show the message
  and stop; do not force-delete branches or retry with other commands.
