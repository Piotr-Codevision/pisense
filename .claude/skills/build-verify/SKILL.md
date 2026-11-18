---
name: build-verify
description: Full PiSense host check - configure, build, unit tests, clang-format check, clang-tidy, optionally code coverage - with a compact PASS/FAIL summary. Use before committing or opening a PR, or when asked to build and test.
argument-hint: "[--coverage]"
allowed-tools: Bash(scripts/dev.sh *)
context: fork
model: haiku
---

# Build and verify PiSense

Rules:
- Make exactly one Bash call with the command below, exactly as written: no `cd` prefix (the working directory is already the project root), no parallel or repeated calls. Do not run cmake, ctest or other tools directly.
- Report the printed step lines and the final `RESULT:` line verbatim; add nothing else unless a step failed.
- Never say the build or tests pass unless the output ends with `RESULT: PASS`.
- On `RESULT: FAIL (<step>)`: show the excerpt, name the failed step, and stop. Do not edit files or open the full log unless the user asked you to fix the failure.
- Exit code 2 means a usage error: show the usage text.

Command:

```sh
scripts/dev.sh build-verify $ARGUMENTS
```
