# PiSense Development

This document describes the development toolchain, environment and related decisions.

## Decisions

### DEV #1: Use CMake as a build system
- **Decision:** CMake (minimum 3.16) with out-of-source builds in `build/`.
- **Rationale:** De-facto standard for C++ projects, broad IDE support, toolchain files
  for cross-compilation, and readily available on Raspberry Pi OS.

### DEV #2: Use clang for cross-platform compilation
- **Status:** Accepted — cross-build verified on a Raspberry Pi Zero W (Raspbian 11
  Bullseye) on 2026-11-17.
- **Decision:** clang/clang++ is the project compiler for both host builds and
  Raspberry Pi cross-builds; Pi binaries are linked with lld against a sysroot copied
  from the target.
- **Rationale:** A single clang installation can generate code for other architectures via
  `--target=`, so no separate GCC ARM toolchain is needed. Also offers good diagnostics
  and tooling (clang-format, clang-tidy).
- **Cross-compilation setup:**
  - **Toolchain file** `cmake/toolchain-rpi-zero.cmake`: target `arm-linux-gnueabihf`,
    CPU flags `-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard -marm`, linker
    `--ld-path=<ld.lld>`, libraries/headers searched only in the sysroot.
  - **Sysroot** copied from the Pi by `scripts/sync-sysroot.sh` (`/usr/include`,
    `/usr/lib/arm-linux-gnueabihf`, `/usr/lib/gcc/arm-linux-gnueabihf/<gcc>`, the dynamic
    loader); absolute symlinks are rewritten to stay inside the sysroot. It must come from
    **Raspberry Pi OS**: stock Debian/Ubuntu `armhf` sysroots are built for ARMv7 and
    produce binaries that crash on the Pi Zero W with `SIGILL`.
  - Binaries link against the Pi's own glibc/libstdc++, so they never require newer
    versions than the target has.
  - `scripts/deploy.sh` copies the binary to the Pi and optionally runs it.
- **Note:** The compiler is selected at configure time, not hardcoded in `CMakeLists.txt`.

### DEV #3: Use GoogleTest for host-based unit testing
- **Decision:** GoogleTest (with GoogleMock) is the unit-test framework for
  hardware-independent components, run on the development host via CTest.
- **Rationale:** Widely used, mature C++ test framework; GoogleMock allows replacing
  hardware interfaces with mocks so logic can be tested without a Raspberry Pi.
- **Integration:** An installed GoogleTest (>= 1.11, CMake config package) is used if
  found; otherwise v1.17.0 is fetched at configure time via CMake `FetchContent`
  (pinned URL + SHA256). In the fetch case the first configure needs network access.
- **Scope:** Tests are built when `PISENSE_BUILD_TESTS=ON` (default on host builds,
  off when cross-compiling). Unit tests live in `tests/unit/`.
- **Native builds on the Raspberry Pi:** pass `-DPISENSE_BUILD_TESTS=OFF` — building
  GoogleTest on a Pi Zero W is slow and requires network access.

### DEV #4: Use clang-format for code style
- **Decision:** All C++ sources are formatted with clang-format using the repository's
  `.clang-format`: LLVM base style, Stroustrup braces (own line for function definitions,
  and for `else`/`catch`; same line for `if`/`for`/`class`), 4-space indent, 100 columns.
- **Rationale:** Consistent style enforced by a tool instead of reviews; ships with the
  clang toolchain (DEV #2); supported by all major editors (format on save).
- **Usage:** CMake targets `format` (rewrites files) and `format-check` (fails on
  unformatted code). They are only available if clang-format is found at configure time.

### DEV #5: Use clang-tidy for static code analysis
- **Decision:** C++ sources are analyzed with clang-tidy using the repository's
  `.clang-tidy`. Enabled check groups: `bugprone`, `clang-analyzer`, `cppcoreguidelines`,
  `misc`, `modernize`, `performance`, `portability`, `readability`. A few noisy checks are
  disabled (magic numbers, trailing return types, identifier length, include-cleaner,
  easily-swappable parameters, non-private members). `tests/.clang-tidy` additionally
  disables checks triggered by GoogleTest macros.
- **Rationale:** Catches bugs and outdated or unsafe constructs early; part of the clang
  toolchain (DEV #2); works on the compilation database produced by CMake (DEV #1).
- **Usage:**
  - `tidy` target: analyzes all project sources on demand.
  - `PISENSE_ENABLE_CLANG_TIDY=ON` (default OFF): runs clang-tidy during compilation of
    project targets (`pisense`, `pisense_unit_tests`); third-party code is not analyzed.
  - Findings are warnings, not errors, for now; this may be tightened once the codebase
    grows.

### DEV #6: Measure code coverage with clang source-based coverage
- **Decision:** Host unit tests can be built with clang source-based coverage
  (`-fprofile-instr-generate -fcoverage-mapping`). The `coverage` target runs the tests,
  merges the profiles with `llvm-profdata` and reports with `llvm-cov`: a console
  summary, an HTML report and an lcov file.
- **Rationale:** Part of the clang toolchain (DEV #2), so no additional dependency.
  Precise line, function, region and branch metrics taken from the compiler's AST,
  better than gcov-style instrumentation with clang. The lcov export works with most CI
  and coverage services; gcovr can convert it if Cobertura XML is ever needed.
  Alternatives considered: `--coverage` + gcovr, `--coverage` + lcov/genhtml.
- **Scope:**
  - Measured: project code in `src/` and `inc/`. Product code is built as the
    `pisense_core` library, linked by both the `pisense` executable and the unit tests,
    so the tests exercise the same code as the application. `src/main.cpp` stays thin and
    is not measured.
  - Excluded: test code (`tests/`), third-party code (`_deps/`) and system headers.
  - Enabled by `PISENSE_ENABLE_COVERAGE=ON` (default OFF) in a separate build
    directory; host builds with clang only (configure fails otherwise). Instrumentation
    flags come from the `pisense_coverage` INTERFACE target, linked by project targets
    only.
  - `llvm-profdata`/`llvm-cov` must match the clang version; versioned names
    (e.g. `llvm-cov-21`) are preferred.
- **Thresholds:** none for now (report only, MVP). A minimum (e.g. line coverage) may
  be enforced later.

### DEV #7: Wrap repeatable procedures in `scripts/dev.sh` and Claude Code skills
- **Decision:** Build and verification procedures (configure, build, ctest, format-check,
  tidy, coverage, cross-build) are wrapped in one script, `scripts/dev.sh`, with a fixed
  compact output contract. Three thin Claude Code skills (`build`, `verify`,
  `build-verify`) call it in a forked Haiku subagent.
- **Rationale:** One command replaces 4–10 ad-hoc tool calls. Project specifics (clang++,
  separate build directories, ctest without `--test-dir` for CMake 3.16, clang-tidy
  findings treated as failures) live in the script, not in the model's memory. Raw tool
  logs stay on disk, and only a few summary lines reach the model, so cheaper models run
  the procedures reliably. Humans and CI can use the same script.
  Alternatives considered:
  - skills with instructions only (same verbose logs, room for deviation);
  - CMakePresets (requires CMake ≥ 3.19, above the 3.16 minimum);
  - a Makefile wrapper (a second front-end with no output reduction).
- **Measured (S1: "build and run all checks", clean tree, warm build, 2026-11-18):**

  | Session model | Variant | Turns | Output tok | Context tok (cache r+w) | Duration |
  |---|---|---|---|---|---|
  | Haiku | no skill | 10 | 2,606 | 282k | 44 s |
  | Haiku | `build-verify` skill | 2 | 325 | 58k | 33 s |
  | Sonnet | no skill | 6 | 1,208 | 185k | 40 s |
  | Sonnet | `build-verify` skill | 2 | 209 | 57k | 34 s |

  Every run gave the correct verdict. Without the skill, Haiku also wrote an unrequested
  log file. Dollar cost depends heavily on prompt-cache state: with cold caches in both
  variants it was 13–16% lower with the skill. The token and turn reductions above are the
  stable effect.
- **Scope:** host build, tests, format-check, tidy, coverage, and the rpi cross-build
  (which needs an existing sysroot). Sysroot sync and deployment stay manual, because they
  reach the Pi and need credentials.

### DEV #8: Script the GitHub pull-request flow (`scripts/git-flow.sh`, user-invoked skills)
- **Decision:** `scripts/git-flow.sh pr` commits on a feature branch, pushes and opens (or
  reuses) a pull request; `scripts/git-flow.sh merged` fast-forwards the default branch and
  deletes the merged feature branch locally and remotely. The Claude Code skills
  `/commit-push-pr` and `/pr-merged` wrap it and run only when the user invokes them
  (`disable-model-invocation: true`), because committing and pushing need an explicit
  request.
- **Rationale:** Token savings in the commit step itself are small (about 10–20%): the
  commit message and PR description must still be written by the session that knows the
  change, so that skill runs in the main conversation, not in a forked cheaper model. The
  gain is reliability: fixed mechanics (HTTPS push with GitHub CLI credentials, PR creation
  through the REST API, squash-merge aware branch deletion) and pre-commit checks that
  previously needed follow-up commits (e.g. files hidden by `.gitignore`). The larger
  saving is post-merge: syncing the default branch and deleting the branch become one
  command instead of two conversation turns, and each turn re-reads the whole conversation.
  Alternatives considered: instruction-only skills (no change compared to remembered
  commands), GitHub CLI `gh pr create`/`gh pr merge` (`gh pr edit` fails with a GraphQL
  deprecation error in the tested setup; the REST API works).
- **No personal or machine data in the repository:** the repository and its URL are read
  from the `origin` remote at runtime; nothing about users, hosts or credentials is stored.
  Before committing, `git-flow.sh pr` scans the added lines of the staged diff, the commit
  message and the PR description for home paths, IPv4 addresses, e-mail addresses (except
  `noreply@`), credential variables, private-key headers and GitHub tokens, and refuses with
  `RESULT: FAIL (sensitive-data)`, listing only file, line and kind (never the matched
  text); `--allow-sensitive` overrides after review. Files such as `.env`, `*.pem` or
  `settings.local.json` are refused outright.
- **Scope:** GitHub remotes only; requires the GitHub CLI (`gh`) to be logged in. The
  attribution lines of commits and PRs are written by the session, not hard-coded.

## Environment

| Component                     | Required      | Tested locally |
|-------------------------------|---------------|----------------|
| OS (host)                     | Linux         | Ubuntu (WSL2)  |
| CMake                         | >= 3.16       | 4.2.3          |
| clang                         | >= 14         | 21.1.8         |
| clang-format                  | >= 14         | 21.1.8         |
| clang-tidy                    | >= 14         | 21.1.8         |
| lld                           | >= 14         | 18.1.8         |
| llvm-cov / llvm-profdata      | same as clang | 21.1.8         |
| file (for `dev.sh build rpi`) | any           | 5.46           |
| shellcheck (optional)         | any           | 0.11.0         |

### Target (Raspberry Pi Zero W, checked 2026-11-17)

| Item          | Value                                                  |
|---------------|--------------------------------------------------------|
| Board         | Raspberry Pi Zero W Rev 1.1                            |
| OS            | Raspbian GNU/Linux 11 (Bullseye), 32-bit `armhf`       |
| Kernel        | 6.1.21+ (`armv6l`)                                     |
| CPU           | ARM1176JZF-S, ARMv6, VFPv2, hard-float ABI             |
| glibc         | 2.31                                                   |
| libstdc++     | 6.0.28 (GCC 10.2.1, up to `GLIBCXX_3.4.28`)            |
| Memory / disk | 429 MiB RAM, 26 GB SD card                             |
| Libraries     | `libgpiod-dev` 1.6.2 installed                         |
| Interfaces    | `gpiochip0`; I2C/SPI not enabled in `/boot/config.txt` |

Native builds on the Pi are possible (CMake 3.18.4, GCC 10.2.1) but slow; cross-building
on the host is the default workflow.

## Quick checks (`scripts/dev.sh`)

One command per repeatable procedure (DEV #7), with compact output: one `[PASS|FAIL] <step>
(<secs>s)` line per step (`[SKIP] <step> (<reason>)` for an optional step that was not run),
a short error excerpt for a failed step and a final `RESULT: PASS [(skipped: <steps>)]` or
`RESULT: FAIL (<step>)` line (exit code 0/1). Full logs are in `<build dir>/logs/<step>.log`.

```sh
scripts/dev.sh build [host|rpi|coverage]   # configure + build (default: host)
scripts/dev.sh verify [--coverage]         # rebuild, ctest, format-check, shellcheck, tidy (+ coverage)
scripts/dev.sh build-verify [--coverage]   # build host, then verify
```

- `verify` needs an existing host build and fails on any clang-tidy finding; a missing
  clang-format/clang-tidy is reported as such, not as a code failure.
- `verify` runs the `shellcheck` target (see Static analysis) when shellcheck is installed;
  any finding, including info/style notes, fails the step. Without shellcheck it prints
  `[SKIP] shellcheck (not installed)` and ends with `RESULT: PASS (skipped: shellcheck)`.
- The script owns `build/`, `build-rpi/` and `build-coverage/` and always configures them
  with the documented options (e.g. clang++); use another directory for custom configs.
- `build rpi` needs the sysroot (see below); it never syncs it or deploys.
- The manual commands below remain valid; the script only wraps them.

## Build (host)

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
./build/pisense
```

## Unit tests (host)

```sh
cmake -S . -B build -DCMAKE_CXX_COMPILER=clang++
cmake --build build
(cd build && ctest --output-on-failure)
```

- To skip building tests, add `-DPISENSE_BUILD_TESTS=OFF` to the configure command.
- Offline: install GoogleTest (e.g. `libgtest-dev` / `googletest` package providing
  `GTestConfig.cmake`), or point CMake at a pre-downloaded source tree with
  `-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=<path>`.

## Code coverage (host)

```sh
cmake -S . -B build-coverage -DCMAKE_CXX_COMPILER=clang++ -DPISENSE_ENABLE_COVERAGE=ON
cmake --build build-coverage --target coverage
```

- The console shows a per-file summary (regions, functions, lines, branches).
- HTML report: `build-coverage/coverage/html/index.html`.
- lcov file (for CI/IDE plugins): `build-coverage/coverage/coverage.lcov`.
- Each run starts from a clean `build-coverage/coverage/` directory. Failing tests do not
  stop the report; a warning is printed instead.

## Code formatting

```sh
cmake --build build --target format        # format all sources in place
cmake --build build --target format-check  # verify formatting (fails on violations)
```

## Static analysis

```sh
cmake --build build --target tidy                         # analyze all project sources
cmake -S . -B build -DPISENSE_ENABLE_CLANG_TIDY=ON         # or: analyze on every compile
```

Shell scripts (`scripts/`, `cmake/`, `.claude/`, any depth, `*.sh`) are linted with
shellcheck when it is installed (optional; the target is not defined otherwise):

```sh
cmake --build build --target shellcheck
```

## Cross-build for Raspberry Pi

```sh
# 1. Copy the sysroot from the Pi (once, and after installing new -dev packages on the Pi)
PI_HOST=pi@<pi-address> scripts/sync-sysroot.sh          # -> $HOME/rpi-sysroot

# 2. Configure and build (tests are off by default when cross-compiling)
cmake -S . -B build-rpi -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-rpi-zero.cmake
cmake --build build-rpi

# 3. Deploy to the Pi and run
PI_HOST=pi@<pi-address> scripts/deploy.sh --run
```

- Override the sysroot location with `RPI_SYSROOT=<dir>` (script and CMake) or
  `-DRPI_SYSROOT=<dir>`.
- The scripts use `ssh`/`rsync`; set up key-based login (`ssh-copy-id pi@<pi-address>`)
  or override the SSH command with `PI_SSH`.

## Claude Code skills

Project skills in `.claude/skills/` (DEV #7) wrap `scripts/dev.sh`: `/build [host|rpi|coverage]`,
`/verify [--coverage]` and `/build-verify [--coverage]`. Claude also picks them
automatically for build/test requests. Each runs in a forked Haiku subagent
(`context: fork`, `model: haiku`) and returns only the summary to the main conversation.

`/commit-push-pr [branch-name] [description]` and `/pr-merged [branch-name]` (DEV #8) wrap
`scripts/git-flow.sh`. They run only when invoked by the user. `/commit-push-pr` runs in the
main conversation (it writes the commit message and PR description), runs `/build-verify`
first when code changed, and stops on possible personal or secret data.

```sh
scripts/git-flow.sh pr --message-file <file> --body-file <file> [--branch <name>] [--add <path>]...
scripts/git-flow.sh merged [<branch>]
```

## Claude Code hooks

Project hooks are configured in `.claude/settings.json` (scripts in `.claude/hooks/`):

- **PreToolUse / Bash — `guard-rm-rf.py`:** a recursive `rm` (`-r`/`-R`/`--recursive`,
  with or without `-f`) requires explicit user confirmation unless every target is inside
  the project (except the project root and `.git`), inside a temporary directory (`/tmp`,
  `/var/tmp`, `$TMPDIR`), or non-existent. Targets that cannot be resolved before running
  (unknown variables, command substitution, `xargs`, `find -exec`) also ask. Pure path
  checks; symlinks are resolved so a link cannot escape the project. Only a standalone
  `rm` word is considered (not `format`, `confirm`, ...). Heredoc bodies are skipped as
  data unless fed to a shell (`bash`, `sh`, `ssh`, `sudo`, ...). A line that cannot be
  parsed (e.g. an unbalanced quote) asks only if it contains `rm`, quoting that line.
- **Stop — `format-and-tidy.py`:** C/C++ files changed in `src/`, `inc/`, `tests/` are
  formatted with clang-format (DEV #4) and analysed with clang-tidy (DEV #5) using
  `build/compile_commands.json` (override with `PISENSE_TIDY_BUILD_DIR`). clang-tidy
  findings are fed back to Claude once before it may finish.
