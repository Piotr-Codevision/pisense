#!/usr/bin/env python3
"""Claude Code Stop hook: clang-format and clang-tidy the C/C++ files Claude changed.

Changed files = files under src/, inc/, tests/ that differ from HEAD (staged or not)
plus new untracked files (DEV #4 / DEV #5 in docs/development.md).

  * clang-format: files are formatted in place; the user is told which ones changed.
  * clang-tidy:   changed .cpp files are analysed with the build's compilation
                  database. Findings block the stop once, so Claude can fix them; on the
                  follow-up stop (stop_hook_active) they are only reported, to avoid loops.

Environment:
  PISENSE_TIDY_BUILD_DIR  build directory with compile_commands.json (default: build)
"""

import json
import os
import shutil
import subprocess
import sys

SOURCE_DIRS = ("src/", "inc/", "tests/")
CXX_EXTENSIONS = (".cpp", ".cc", ".cxx", ".h", ".hpp", ".hh")
TIDY_EXTENSIONS = (".cpp", ".cc", ".cxx")
VERSIONS = range(25, 13, -1)
MAX_REASON_CHARS = 6000


def find_tool(name):
    for candidate in [name] + [f"{name}-{v}" for v in VERSIONS]:
        path = shutil.which(candidate)
        if path:
            return path
    return None


def git_lines(project, *args):
    result = subprocess.run(
        ["git", "-C", project, *args], capture_output=True, text=True
    )
    return result.stdout.splitlines() if result.returncode == 0 else []


def changed_files(project):
    names = set(git_lines(project, "diff", "--name-only", "--diff-filter=d", "HEAD"))
    names |= set(git_lines(project, "ls-files", "--others", "--exclude-standard"))
    return sorted(
        n for n in names
        if n.startswith(SOURCE_DIRS)
        and n.endswith(CXX_EXTENSIONS)
        and os.path.isfile(os.path.join(project, n))
    )


def run_clang_format(tool, project, files):
    """Format files in place; return the list of files that were changed."""
    reformatted = []
    for name in files:
        check = subprocess.run(
            [tool, "--dry-run", "--Werror", name],
            cwd=project, capture_output=True, text=True,
        )
        if check.returncode != 0:
            subprocess.run([tool, "-i", name], cwd=project, check=True)
            reformatted.append(name)
    return reformatted


def run_clang_tidy(tool, project, build_dir, files):
    """Return clang-tidy findings (warnings/errors) as text, empty if clean."""
    result = subprocess.run(
        [tool, "-p", build_dir, "--quiet", *files],
        cwd=project, capture_output=True, text=True,
    )
    findings = []
    keep = False
    for line in result.stdout.splitlines():
        if ": warning: " in line or ": error: " in line:
            keep = True
        elif line and not line.startswith(" ") and ": note: " not in line:
            keep = False
        if keep:
            findings.append(line)
    return "\n".join(findings).strip()


def main():
    payload = json.load(sys.stdin)
    project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    files = changed_files(project)
    if not files:
        return

    messages = []

    clang_format = find_tool("clang-format")
    if clang_format:
        reformatted = run_clang_format(clang_format, project, files)
        if reformatted:
            messages.append("clang-format reformatted: " + ", ".join(reformatted))
    else:
        messages.append("clang-format not found: formatting skipped")

    tidy_files = [f for f in files if f.endswith(TIDY_EXTENSIONS)]
    findings = ""
    if tidy_files:
        clang_tidy = find_tool("clang-tidy")
        build_dir = os.path.join(
            project, os.environ.get("PISENSE_TIDY_BUILD_DIR", "build")
        )
        if not clang_tidy:
            messages.append("clang-tidy not found: analysis skipped")
        elif not os.path.isfile(os.path.join(build_dir, "compile_commands.json")):
            messages.append(
                f"clang-tidy skipped: no compile_commands.json in {build_dir} "
                "(configure the host build first)"
            )
        else:
            findings = run_clang_tidy(clang_tidy, project, build_dir, tidy_files)
            if not findings:
                messages.append("clang-tidy: no findings in " + ", ".join(tidy_files))

    output = {}
    if findings and not payload.get("stop_hook_active"):
        output["decision"] = "block"
        output["reason"] = (
            "clang-tidy reported findings in the changed files. Fix them (or explain "
            "why a finding should be suppressed) before finishing:\n"
            + findings[:MAX_REASON_CHARS]
        )
    elif findings:
        messages.append("clang-tidy findings remain (not blocking again):\n" + findings[:2000])

    if messages:
        output["systemMessage"] = "\n".join(messages)
    if output:
        json.dump(output, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never break the session because of the hook itself
        json.dump({"systemMessage": f"format/tidy Stop hook failed: {exc}"}, sys.stdout)
