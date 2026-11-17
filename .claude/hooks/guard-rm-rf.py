#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash): require user confirmation for `rm -rf`.

A recursive+forced `rm` is let through to the normal permission flow only when every
target is:
  * non-existent, or
  * inside a temporary directory (/tmp, /var/tmp, $TMPDIR), or
  * created during the current Claude session (it and everything below it have a file
    birth time later than the session transcript).

Anything else -- including targets that cannot be resolved statically (variables, globs,
command substitution, xargs, find -exec) -- makes the hook answer "ask", so the user must
confirm the command explicitly. The hook never auto-approves a command, and any internal
error also results in "ask".
"""

import json
import os
import shlex
import subprocess
import sys

TEMP_ROOTS = ["/tmp", "/var/tmp"]
WRAPPERS = {"sudo", "env", "command", "builtin", "nice", "nohup", "time", "exec"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")"}
UNRESOLVABLE_CHARS = set("$`*?[]{}")


def respond_ask(reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.exit(0)


def temp_roots():
    roots = list(TEMP_ROOTS)
    tmpdir = os.environ.get("TMPDIR")
    if tmpdir and os.path.realpath(tmpdir) != "/":
        roots.append(os.path.realpath(tmpdir))
    return roots


def birth_time(path):
    """File birth time in seconds, or None if unknown."""
    try:
        out = subprocess.run(
            ["stat", "-c", "%W", path], capture_output=True, text=True, check=True
        ).stdout.strip()
        value = int(out)
        return value if value > 0 else None
    except (subprocess.CalledProcessError, ValueError, OSError):
        return None


def iter_tree(path):
    """Yield path and every entry below it, without following symlinks."""
    yield path
    if os.path.isdir(path) and not os.path.islink(path):
        for root, dirs, files in os.walk(path, followlinks=False):
            for name in dirs + files:
                yield os.path.join(root, name)


def created_in_session(path, session_start, batch_size=512):
    """True if path and all entries below it were born at/after session_start.

    Uses coreutils `stat` (statx-based) for birth times; GNU find's %B is not reliable.
    `stat` does not follow symlinks, so a link's own birth time is checked.
    """

    def batch_ok(batch):
        result = subprocess.run(
            ["stat", "-c", "%W", "--", *batch], capture_output=True, text=True
        )
        if result.returncode != 0:
            return False
        for value in result.stdout.split():
            born = int(value)
            if born <= 0 or born < session_start:
                return False
        return True

    batch = []
    for entry in iter_tree(path):
        batch.append(entry)
        if len(batch) >= batch_size:
            if not batch_ok(batch):
                return False
            batch = []
    return batch_ok(batch) if batch else True


def split_segments(command):
    """Split a shell command into simple-command token lists."""
    segments = []
    for line in command.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = "#"
        current = []
        for token in lexer:
            if token in SEPARATORS:
                if current:
                    segments.append(current)
                current = []
            else:
                current.append(token)
        if current:
            segments.append(current)
    return segments


def parse_rm(args):
    """Return (recursive, force, operands) for the arguments following `rm`."""
    recursive = force = False
    operands = []
    end_of_options = False
    for arg in args:
        if not end_of_options and arg == "--":
            end_of_options = True
        elif not end_of_options and arg.startswith("--"):
            recursive |= arg == "--recursive"
            force |= arg == "--force"
        elif not end_of_options and arg.startswith("-") and len(arg) > 1:
            recursive |= "r" in arg or "R" in arg
            force |= "f" in arg
        else:
            operands.append(arg)
    return recursive, force, operands


def resolve(operand, cwd):
    """Absolute path of operand, or None if it cannot be resolved statically."""
    if any(c in UNRESOLVABLE_CHARS for c in operand):
        return None
    if operand == "~" or operand.startswith("~/"):
        operand = os.path.expanduser(operand)
    elif operand.startswith("~"):
        return None
    if not os.path.isabs(operand):
        if cwd is None:
            return None
        operand = os.path.join(cwd, operand)
    operand = os.path.normpath(operand)
    # Resolve symlinks in the parent only: `rm -rf link` removes the link itself.
    parent, name = os.path.split(operand)
    return os.path.join(os.path.realpath(parent), name) if name else operand


def contains_git_tracked(path):
    """True if path is, or contains, a file tracked by git.

    Birth time alone is not proof of authorship: `git checkout`/`git switch` and many
    editors recreate files, giving user-authored content a fresh birth time.
    """
    base = path if os.path.isdir(path) and not os.path.islink(path) else os.path.dirname(path)
    inside = subprocess.run(
        ["git", "-C", base, "rev-parse", "--is-inside-work-tree"],
        capture_output=True, text=True,
    )
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        # Not in a work tree: still protect a repository's own .git directory.
        return os.path.basename(path) == ".git"
    if os.path.basename(path) == ".git":
        return True
    tracked = subprocess.run(
        ["git", "-C", base, "ls-files", "-z", "--", path],
        capture_output=True, text=True,
    )
    return tracked.returncode != 0 or bool(tracked.stdout)


def check_target(path, session_start):
    """Return None if deleting path is fine, otherwise a reason string."""
    if not os.path.lexists(path):
        return None
    for root in temp_roots():
        if path.startswith(root.rstrip("/") + "/"):
            return None
    if contains_git_tracked(path):
        return "contains files tracked by git"
    if session_start is not None and created_in_session(path, session_start):
        return None
    return "not temporary and not created in this Claude session"


def main():
    payload = json.load(sys.stdin)
    if payload.get("tool_name") != "Bash":
        return
    command = payload.get("tool_input", {}).get("command", "")
    if "rm" not in command:
        return

    cwd = payload.get("cwd") or os.getcwd()
    transcript = payload.get("transcript_path")
    session_start = birth_time(transcript) if transcript and os.path.exists(transcript) else None

    problems = []
    for tokens in split_segments(command):
        # Track `cd` so relative operands resolve against the right directory.
        if tokens[0] == "cd":
            if len(tokens) == 1:
                cwd = os.path.expanduser("~")
            else:
                cwd = resolve(tokens[1], cwd)
            continue

        for i, token in enumerate(tokens):
            if os.path.basename(token) != "rm":
                continue
            # Only treat it as a command if everything before it is a wrapper/assignment.
            prefix = tokens[:i]
            if any(t in ("xargs", "-exec", "-execdir", "-ok") for t in prefix):
                recursive, force, _ = parse_rm(tokens[i + 1:])
                if recursive and force:
                    problems.append(f"{' '.join(tokens)} (targets come from another command)")
                break
            if not all(t in WRAPPERS or "=" in t or t.startswith("-") for t in prefix):
                continue
            recursive, force, operands = parse_rm(tokens[i + 1:])
            if not (recursive and force):
                break
            for operand in operands:
                path = resolve(operand, cwd)
                if path is None:
                    problems.append(f"{operand} (cannot be resolved before running)")
                    continue
                reason = check_target(path, session_start)
                if reason:
                    problems.append(f"{path} ({reason})")
            break

    if problems:
        respond_ask(
            "rm -rf guard: confirm deletion of path(s) not created by Claude in this "
            "session and not temporary:\n  - " + "\n  - ".join(problems)
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # fail closed: ask instead of silently allowing
        respond_ask(f"rm -rf guard could not analyse the command ({exc}); please confirm.")
