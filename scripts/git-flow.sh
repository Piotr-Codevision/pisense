#!/usr/bin/env bash
# Commit/push/pull-request flow and post-merge sync for GitHub (DEV #8).
#
# The repository (owner/name) is read from the `origin` remote at runtime; nothing about
# users, machines or credentials is stored here. Push and fetch go over HTTPS with the
# GitHub CLI as credential helper, so no SSH key is needed.
#
# Output contract: one [PASS|FAIL|WARN] line per step, final `RESULT: PASS` or
# `RESULT: FAIL (<step>)`; exit code 0 / 1 (2 = usage error).

set -u

usage() {
    cat <<'EOF'
Usage:
  scripts/git-flow.sh pr --message-file <file> --body-file <file>
                         [--branch <name>] [--title <PR title>] [--add <path>]...
                         [--allow-sensitive]
      Commit tracked changes (plus --add paths) on a feature branch, push it and open a
      pull request (or reuse the open one). On the default branch a new branch is created:
      --branch, or derived from the commit subject ("Chore: Add X" -> chore/add-x).
      The PR title defaults to the commit subject.
  scripts/git-flow.sh merged [<branch>]
      After a merge on GitHub: switch to the default branch, fast-forward it and delete
      the merged feature branch (the current one, or <branch>) locally and remotely.
EOF
    exit 2
}

fail() { # fail <step> <message...>
    local step="$1"
    shift
    echo "[FAIL] $step"
    printf '  %s\n' "$@"
    echo "RESULT: FAIL ($step)"
    exit 1
}

pass() { echo "[PASS] $1${2:+ ($2)}"; }

# git with GitHub CLI credentials, ignoring any other configured helper.
git_gh() {
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

# Sets REPO (owner/name), OWNER, PUSH_URL and BASE from the origin remote.
repo_info() {
    local url
    url="$(git remote get-url origin 2>/dev/null)" || fail remote "No 'origin' remote."
    REPO="$(printf '%s' "$url" | sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##')"
    [[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail remote "origin is not a GitHub repository."
    OWNER="${REPO%%/*}"
    PUSH_URL="${GIT_FLOW_PUSH_URL:-https://github.com/$REPO.git}" # override for tests only
    BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
    BASE="${BASE#origin/}"
    BASE="${BASE:-main}"
}

# Patterns for content that must not be published (written so that this file does not
# match itself). Each entry: "<name>|<extended regex>"; matching is case-insensitive.
SENSITIVE_PATTERNS=(
    "home-path|/(home|Users)/[a-z_][a-z0-9_.-]*"
    "ipv4-address|(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)"
    "email-address|[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}"
    "credential|pass[w]or[d]|pass[w]d|sshpas[s]="
    "private-key|-----BEGIN [A-Z ]*PRIVAT[E] KEY"
    "github-token|gh[pousr]_[a-z0-9]{20,}|github_pat_[a-z0-9_]{20,}"
)
# Allowed occurrences of the patterns above.
SENSITIVE_ALLOW='noreply@|git@github\.com|pi@raspberrypi\.local'

# scan_lines: reads "location<TAB>text" lines on stdin, prints "location: <pattern name>"
# for every hit that is not an allowed occurrence. The matched text is never printed.
scan_lines() {
    local input entry loc text
    input="$(cat)"
    for entry in "${SENSITIVE_PATTERNS[@]}"; do
        while IFS=$'\t' read -r loc text; do
            [[ -n $loc ]] || continue
            if printf '%s\n' "$text" | grep -oiE -e "${entry#*|}" | grep -qviE "$SENSITIVE_ALLOW"; then
                echo "$loc: ${entry%%|*}"
            fi
        done < <(printf '%s\n' "$input" | grep -iE -e "${entry#*|}")
    done
}

# Added lines of the staged diff as "file:line<TAB>text".
staged_added_lines() {
    git diff --cached -U0 --no-color --no-ext-diff | awk '
        /^\+\+\+ / { file = substr($0, 7); next }
        /^@@ / { split($3, a, ","); line = substr(a[1], 2) + 0; next }
        /^\+/ { print file ":" line "\t" substr($0, 2); line++ }'
}

# Lines of a text file as "label:line<TAB>text".
file_lines() {
    awk -v label="$2" '{ print label ":" NR "\t" $0 }' "$1"
}

# "Chore: Add X to Y" -> "chore/add-x-to-y"
branch_from_subject() {
    local prefix rest
    prefix="$(printf '%s' "${1%%:*}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
    rest="$(printf '%s' "${1#*:}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' |
        sed -E 's/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')"
    [[ $1 == *:* && -n $prefix && -n $rest ]] || return 1
    echo "${prefix%-}/$rest"
}

cmd_pr() {
    local message="" body="" branch="" title="" allow_sensitive=0
    local -a add=()
    while (($#)); do
        case "$1" in
            --message-file) message="${2:-}"; shift 2 || usage ;;
            --body-file) body="${2:-}"; shift 2 || usage ;;
            --branch) branch="${2:-}"; shift 2 || usage ;;
            --title) title="${2:-}"; shift 2 || usage ;;
            --add) add+=("${2:-}"); shift 2 || usage ;;
            --allow-sensitive) allow_sensitive=1; shift ;;
            *) usage ;;
        esac
    done
    [[ -s $message && -s $body ]] || fail inputs "--message-file and --body-file must be non-empty files."
    local subject
    subject="$(head -n 1 "$message")"
    [[ $subject =~ ^[A-Z][A-Za-z]*:\ .+ ]] || fail inputs "Commit subject must look like 'Prefix: Description', got: $subject"
    title="${title:-$subject}"
    repo_info

    # Branch: create one when on the default branch, otherwise stay on the feature branch.
    local current
    current="$(git branch --show-current)"
    [[ -n $current ]] || fail branch "Detached HEAD; check out a branch first."
    if [[ $current == "$BASE" ]]; then
        branch="${branch:-$(branch_from_subject "$subject")}" ||
            fail branch "Cannot derive a branch name from '$subject'; pass --branch."
        git check-ref-format --branch "$branch" >/dev/null 2>&1 || fail branch "Invalid branch name: $branch"
        git show-ref --verify --quiet "refs/heads/$branch" && fail branch "Branch $branch already exists."
    elif [[ -n $branch && $branch != "$current" ]]; then
        fail branch "Already on feature branch $current; refusing to switch to $branch."
    else
        branch="$current"
    fi

    # Stage tracked changes and the explicitly added paths.
    git add -u || fail stage "git add -u failed."
    if ((${#add[@]})); then
        git add -- "${add[@]}" >/dev/null 2>&1 || fail stage "Could not add: ${add[*]} (ignored or missing?)"
    fi
    git diff --cached --quiet && fail stage "Nothing to commit."

    local staged
    staged="$(git diff --cached --name-only)"
    local forbidden
    forbidden="$(printf '%s\n' "$staged" | grep -iE '(^|/)\.env($|\.)|credential|settings\.local\.json|(^|/)id_(rsa|ed25519|ecdsa)|\.(pem|key|p12)$' || true)"
    [[ -z $forbidden ]] || fail stage "Refusing to commit files that may hold secrets:" "$forbidden"

    # Content check (only line locations and pattern names are printed, never the text).
    local hits
    hits="$({
        staged_added_lines
        file_lines "$message" commit-message
        file_lines "$body" pr-body
    } | scan_lines | head -n 30)"
    if [[ -n $hits ]]; then
        if ((allow_sensitive)); then
            echo "[WARN] sensitive-data (allowed by --allow-sensitive)"
            printf '%s\n' "$hits" | sed 's/^/  /'
        else
            fail sensitive-data "Possible personal/machine/secret data (location: pattern):" \
                "$(printf '%s\n' "$hits" | sed '2,$s/^/  /')" \
                "Remove it, or re-run with --allow-sensitive after review."
        fi
    else
        pass sensitive-data "none found"
    fi

    # Warn about files in project directories that git ignores or that are left untracked.
    local ignored untracked
    ignored="$(git ls-files --others --ignored --exclude-standard --directory -- \
        .claude scripts src inc tests docs cmake config 2>/dev/null |
        grep -vE '(^|/)(settings\.local\.json|__pycache__/?)$|\.(pyc|log)$' || true)"
    if [[ -n $ignored ]]; then
        echo "[WARN] ignored files in project directories (not committed):"
        printf '%s\n' "$ignored" | sed 's/^/  /'
    fi
    untracked="$(git ls-files --others --exclude-standard)"
    if [[ -n $untracked ]]; then
        echo "[WARN] untracked files (not committed; use --add):"
        printf '%s\n' "$untracked" | sed 's/^/  /'
    fi

    if [[ $current == "$BASE" ]]; then
        git checkout -q -b "$branch" || fail branch "Cannot create branch $branch."
    fi
    git commit -q -F "$message" || fail commit "git commit failed."
    pass commit "$(git log -1 --format='%h %s')"

    git_gh push -q "$PUSH_URL" "$branch" >/dev/null 2>&1 || fail push "Push of $branch to $REPO failed."
    git update-ref "refs/remotes/origin/$branch" HEAD
    pass push "$REPO $branch"

    local url
    url="$(gh api "repos/$REPO/pulls?head=$OWNER:$branch&state=open" --jq '.[0].html_url // empty' 2>/dev/null)"
    if [[ -n $url ]]; then
        pass pr "updated $url"
    else
        url="$(gh api "repos/$REPO/pulls" -f title="$title" -f head="$branch" -f base="$BASE" \
            -F body=@"$body" --jq .html_url 2>&1)" || fail pr "Creating the pull request failed: $url"
        pass pr "created $url"
    fi
    echo "RESULT: PASS"
}

# True if <branch> is merged into the default branch: by ancestry, or (for squash and
# rebase merges) by a merged pull request on GitHub.
is_merged() {
    git merge-base --is-ancestor "$1" "$BASE" 2>/dev/null && return 0
    [[ -n "$(gh api "repos/$REPO/pulls?head=$OWNER:$1&state=closed" \
        --jq '[.[] | select(.merged_at != null)] | .[0].number // empty' 2>/dev/null)" ]]
}

cmd_merged() {
    (($# <= 1)) || usage
    repo_info
    local branch="${1:-$(git branch --show-current)}"
    [[ $branch == "$BASE" ]] && branch=""
    if ! git diff --quiet || ! git diff --cached --quiet; then
        fail sync "Uncommitted changes in tracked files; commit or stash them first."
    fi

    git checkout -q "$BASE" || fail sync "Cannot check out $BASE."
    git_gh fetch -q "$PUSH_URL" "$BASE" >/dev/null 2>&1 || fail sync "Fetching $BASE from $REPO failed."
    git merge -q --ff-only FETCH_HEAD >/dev/null 2>&1 || fail sync "Local $BASE cannot be fast-forwarded to $REPO $BASE."
    git update-ref "refs/remotes/origin/$BASE" FETCH_HEAD
    pass sync "$BASE at $(git log -1 --format='%h %s')"

    if [[ -z $branch ]]; then
        echo "  no feature branch given; nothing to delete"
    else
        git show-ref --verify --quiet "refs/heads/$branch" || fail delete-branch "No local branch $branch."
        is_merged "$branch" || fail delete-branch "$branch is not merged into $BASE (no merged PR found); not deleted."
        if [[ -n "$(git_gh ls-remote --heads "$PUSH_URL" "$branch" 2>/dev/null)" ]]; then
            git_gh push -q "$PUSH_URL" --delete "$branch" >/dev/null 2>&1 ||
                fail delete-branch "Deleting remote branch $branch failed."
        fi
        git branch -q -D "$branch" || fail delete-branch "Deleting local branch $branch failed."
        git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null || true
        pass delete-branch "$branch, local and remote"
    fi
    echo "RESULT: PASS"
}

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || fail repo "Not inside a git repository."
command -v gh >/dev/null || fail tools "GitHub CLI 'gh' not found."
cmd="${1:-}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
    pr) cmd_pr "$@" ;;
    merged) cmd_merged "$@" ;;
    *) usage ;;
esac
