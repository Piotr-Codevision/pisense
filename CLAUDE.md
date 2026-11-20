# CLAUDE.md

## Project Overview
PiSense is an educational IoT environmental monitoring project built in modern C++ for Raspberry Pi Zero W. It measures temperature and humidity, controls LED status indicators, stores readings, and provides a lightweight REST API.

## Development Guidelines
- Use **C++17** and CMake.
- Follow a modular, layered architecture with clear separation of concerns.
- Keep hardware-specific code isolated behind interfaces.
- Prefer simple, maintainable solutions and minimize external dependencies.
- Ensure compatibility with Raspberry Pi Zero W (ARMv6).
- Keep configuration separate from application logic.
- CMake minimum is 3.16: do not use newer features (e.g. `COMMAND_ERROR_IS_FATAL`, `NO_CACHE`, `ctest --test-dir`, CMakePresets).
- Product code goes into the `pisense_core` library (`src/`, public headers in `inc/pisense/`); the `pisense` executable and the unit tests link it. Keep `src/main.cpp` thin.
- Code style: the repo's clang-format and clang-tidy configs are authoritative; use include guards, not `#pragma once`.

## Testing
- Use host-based unit tests for hardware-independent components.
- Provide integration and hardware tests for Raspberry Pi.
- Never claim tests pass unless they have actually been executed.
- Keep the project buildable and testable throughout development.

## Build and Verification
- Use the project skills (wrapping `scripts/dev.sh`): `/build [host|rpi|coverage]`, `/verify [--coverage]`, `/build-verify [--coverage]`. Prefer them over ad-hoc cmake/ctest calls.
- Run `/build-verify` before reporting work as done or committing; only a final line starting with `RESULT: PASS` counts as passing.
- CI (DEV #9): PRs to `main` must pass the required check `build-and-test` (host build + unit tests); bypassing it is the owner's decision only.
- Commands, toolchain versions and decisions: `docs/development.md`.
- Deployment and sysroot sync reach the Raspberry Pi; run them only when asked.

## Working with Claude
- Understand the existing code and project structure before making changes.
- For architectural decisions, explain alternatives and trade-offs before implementation.
- For implementation tasks, work incrementally and keep changes focused.
- Do not introduce dependencies or change architecture without justification.
- Do not commit, push, or modify Git history unless explicitly requested.
- Update documentation when functionality or design decisions change.
- Record architectural or tooling decisions as a DEV #N entry in `docs/development.md` (decision, rationale, alternatives, scope).
- Git: one branch per change; commit subjects use `Prefix: Description` (e.g. `Build:`, `Chore:`, `Docs:`). When asked, deliver with `/commit-push-pr` and sync after a merge with `/pr-merged`.
- Never commit personal or machine-specific data (local paths, IP addresses, user names, e-mail addresses, credentials).

## Current Priority
Focus on building a working MVP first. Avoid premature optimization and unnecessary complexity.
