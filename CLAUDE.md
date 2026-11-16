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

## Testing
- Use host-based unit tests for hardware-independent components.
- Provide integration and hardware tests for Raspberry Pi.
- Never claim tests pass unless they have actually been executed.
- Keep the project buildable and testable throughout development.

## Working with Claude
- Understand the existing code and project structure before making changes.
- For architectural decisions, explain alternatives and trade-offs before implementation.
- For implementation tasks, work incrementally and keep changes focused.
- Do not introduce dependencies or change architecture without justification.
- Do not commit, push, or modify Git history unless explicitly requested.
- Update documentation when functionality or design decisions change.

## Current Priority
Focus on building a working MVP first. Avoid premature optimization and unnecessary complexity.
