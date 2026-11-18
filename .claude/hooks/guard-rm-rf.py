#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash): guard recursive `rm` against deleting content
outside the project.

Every target of `rm -r` (`-R`, `--recursive`; with or without `-f`) must be:
  * inside the project ($CLAUDE_PROJECT_DIR), but not the project root or `.git`, or
  * inside a temporary directory (/tmp, /var/tmp, $TMPDIR), or
  * non-existent.
Otherwise the hook answers "ask", so the user has to confirm the command. Targets that
cannot be resolved statically (unknown variables, command substitution, `xargs`,
`find -exec`) also ask. The hook never approves anything itself and asks on any error.

Pure path checks: no subprocesses, no directory walks.
"""

import json
import os
import shlex
import sys

WRAPPERS = {"sudo", "env", "command", "builtin", "nice", "nohup", "time", "exec"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")"}
GLOB_CHARS = "*?["


def ask(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": reason,
    }}, sys.stdout)
    sys.exit(0)


def is_within(path, root):
    return path == root or path.startswith(root.rstrip("/") + "/")


def segments(command):
    """Yield the token list of every simple command in a shell command string."""
    for line in command.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = "#"
        current = []
        for token in lexer:
            if token in SEPARATORS:
                if current:
                    yield current
                current = []
            else:
                current.append(token)
        if current:
            yield current


def parse_rm(args):
    """Return (recursive, operands) for the arguments of `rm`."""
    recursive, operands, options_done = False, [], False
    for arg in args:
        if options_done or arg == "-" or not arg.startswith("-"):
            operands.append(arg)
        elif arg == "--":
            options_done = True
        elif arg.startswith("--"):
            recursive |= arg == "--recursive"
        else:
            recursive |= "r" in arg or "R" in arg
    return recursive, operands


def resolve(operand, cwd):
    """Absolute, symlink-safe path for operand; None if it cannot be resolved."""
    path = os.path.expandvars(os.path.expanduser(operand))
    if "$" in path or "`" in path or path.startswith("~"):
        return None
    if not os.path.isabs(path):
        if cwd is None:
            return None
        path = os.path.join(cwd, path)
    if path.endswith("/"):
        return os.path.realpath(path)  # trailing slash follows a symlink
    parent, name = os.path.split(os.path.abspath(path))
    return os.path.join(os.path.realpath(parent), name)  # `rm link` removes the link only


def check(operand, cwd, project, temp_roots):
    """Return None if the target is acceptable, else a description of the problem."""
    glob_at = next((i for i, c in enumerate(operand) if c in GLOB_CHARS), None)
    if glob_at is not None:
        # Judge a glob by the directory its matches live in.
        directory, pattern = os.path.split(operand[:glob_at])
        target = resolve(directory or ".", cwd)
        dotfiles = (pattern or operand[glob_at:]).startswith(".")
    else:
        target = resolve(operand, cwd)
    if target is None:
        return f"{operand} (cannot be resolved before running)"

    if glob_at is not None:
        in_project = project and is_within(target, project) and not (
            is_within(target, os.path.join(project, ".git"))
            or (target == project and dotfiles))
        in_temp = any(is_within(target, root) for root in temp_roots)
    else:
        if not os.path.lexists(target):
            return None
        in_project = project and is_within(target, project) and target != project \
            and not is_within(target, os.path.join(project, ".git"))
        in_temp = any(is_within(target, root) and target != root for root in temp_roots)

    if in_project or in_temp:
        return None
    return f"{target} (outside the project and not temporary)"


def main():
    payload = json.load(sys.stdin)
    command = payload.get("tool_input", {}).get("command", "")
    if payload.get("tool_name") != "Bash" or "rm" not in command:
        return

    cwd = payload.get("cwd") or os.getcwd()
    project_env = os.environ.get("CLAUDE_PROJECT_DIR")
    project = os.path.realpath(project_env) if project_env else None
    temp_roots = [os.path.realpath(p) for p in ("/tmp", "/var/tmp", os.environ.get("TMPDIR"))
                  if p and os.path.realpath(p) != "/"]

    problems = []
    for tokens in segments(command):
        if tokens[0] == "cd":
            cwd = os.path.expanduser("~") if len(tokens) == 1 else resolve(tokens[1] + "/", cwd)
            continue
        for i, token in enumerate(tokens):
            if os.path.basename(token) != "rm":
                continue
            prefix = tokens[:i]
            recursive, operands = parse_rm(tokens[i + 1:])
            if not recursive:
                break
            if any(t in ("xargs", "-exec", "-execdir", "-ok") for t in prefix):
                problems.append(f"{' '.join(tokens)} (targets come from another command)")
            elif all(t in WRAPPERS or "=" in t or t.startswith("-") for t in prefix):
                problems += filter(None, (check(op, cwd, project, temp_roots) for op in operands))
            break

    if problems:
        ask("rm guard: confirm recursive deletion outside the project / temp dirs:\n  - "
            + "\n  - ".join(problems))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # fail closed
        ask(f"rm guard could not analyse the command ({exc}); please confirm.")
