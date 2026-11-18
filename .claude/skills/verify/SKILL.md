---
name: verify
description: Verify the existing PiSense host build - incremental rebuild, unit tests (ctest), clang-format check, shellcheck, clang-tidy, optionally code coverage - with a compact PASS/FAIL summary. Use when asked to run tests, check formatting/static analysis, or verify changes.
argument-hint: "[--coverage]"
allowed-tools: Bash(scripts/dev.sh *)
context: fork
model: haiku
---

# Verify PiSense

Rules:
- Make exactly one Bash call with the command below, exactly as written: no `cd` prefix (the working directory is already the project root), no parallel or repeated calls. Do not run cmake, ctest or other tools directly.
- Report the printed step lines and the final `RESULT:` line verbatim; add nothing else unless a step failed.
- Never say the build or tests pass unless the last line starts with `RESULT: PASS`. If it says `(skipped: ...)`, name the skipped steps.
- On `RESULT: FAIL (<step>)`: show the excerpt, name the failed step, and stop. Do not edit files or open the full log unless the user asked you to fix the failure.
- Exit code 2 means a usage error: show the usage text.
- If it fails with "No host build", suggest the `build` or `build-verify` skill.

Command:

```sh
scripts/dev.sh verify $ARGUMENTS
```
