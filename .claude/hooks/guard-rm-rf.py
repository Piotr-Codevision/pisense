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

Pure path checks: no subprocesses, no directory walks. Heredoc bodies are data and are
skipped, unless they are fed to a shell (bash, sh, ssh, ...). A line that cannot be parsed
asks only if it contains a standalone `rm`, and the prompt quotes that line.
"""

import json
import os
import re
import shlex
import sys

WRAPPERS = {"sudo", "env", "command", "builtin", "nice", "nohup", "time", "exec"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")"}
GLOB_CHARS = "*?["
# `rm` as a command word: not part of `format`, `confirm`, `guard-rm-rf.py`, ...
RM_WORD = re.compile(r"(?<![\w.-])rm(?![\w.-])")
HEREDOC = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][\w]*)\2")
# Programs whose heredoc input is executed as shell commands.
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "ssh", "sshpass", "sudo", "su", "env",
          "xargs", "eval", "source", "."}


def ask(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": reason,
    }}, sys.stdout)
    sys.exit(0)


def is_within(path, root):
    return path == root or path.startswith(root.rstrip("/") + "/")


def has_heredoc_operator(line):
    """True if `<<` appears unquoted; a line that cannot be parsed is not trusted as one."""
    try:
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        return "<<" in lexer
    except ValueError:
        return False


def command_lines(command):
    """Yield the lines of a command that the shell executes, skipping heredoc bodies that
    are data for a non-shell program (e.g. `python3 - <<'EOF'`)."""
    lines = command.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        yield line
        heredocs = HEREDOC.findall(line) if has_heredoc_operator(line) else []
        if not heredocs:
            continue
        words = {os.path.basename(w) for w in line.split("<<", 1)[0].split()}
        skip_body = not words & SHELLS
        for strip_tabs, _quote, word in heredocs:
            while i < len(lines):
                body = lines[i].lstrip("\t") if strip_tabs else lines[i]
                i += 1
                if body == word:
                    break
                if not skip_body:
                    yield lines[i - 1]


def segments(line):
    """Return the token lists of the simple commands in one line; raises ValueError if the
    line cannot be parsed (e.g. an unbalanced quote)."""
    lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = "#"
    result, current = [], []
    for token in lexer:
        if token in SEPARATORS:
            if current:
                result.append(current)
            current = []
        else:
            current.append(token)
    if current:
        result.append(current)
    return result


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
    if project and (target == project or is_within(target, os.path.join(project, ".git"))):
        return f"{target} (project root or .git)"
    return f"{target} (outside the project and not temporary)"


def parsed(lines, problems):
    """Yield the simple commands of all lines; an unparsable line is a problem only if it
    contains a standalone `rm`."""
    for line in lines:
        try:
            yield from segments(line)
        except ValueError as exc:
            if RM_WORD.search(line):
                problems.append(f"line could not be parsed ({exc}): {line.strip()[:200]}")


def main():
    payload = json.load(sys.stdin)
    command = payload.get("tool_input", {}).get("command", "")
    if payload.get("tool_name") != "Bash" or not RM_WORD.search(command):
        return

    cwd = payload.get("cwd") or os.getcwd()
    project_env = os.environ.get("CLAUDE_PROJECT_DIR")
    project = os.path.realpath(project_env) if project_env else None
    temp_roots = [os.path.realpath(p) for p in ("/tmp", "/var/tmp", os.environ.get("TMPDIR"))
                  if p and os.path.realpath(p) != "/"]

    problems = []
    for tokens in parsed(command_lines(command), problems):
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
