# Shared helpers for the PR Reviewer scripts. POSIX sh; needs git, and gh for anything touching GitHub.

# The `command` of the tool call a hook receives as JSON on stdin (Bash and PowerShell tools).
tool_command() {
  input=$(cat)
  out=''
  command -v jq >/dev/null 2>&1 &&
    out=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -n "$out" ] || ! command -v node >/dev/null 2>&1 ||
    out=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String((JSON.parse(s).tool_input||{}).command||""))}catch(e){}})' 2>/dev/null)
  # ponytail: no working JSON parser; the raw JSON still holds the command text. JSON punctuation becomes spaces
  # so words like `main` still end at a space for the patterns.
  [ -n "$out" ] || out=$(printf '%s' "$input" | tr '"{},' '    ')
  printf '%s' "$out" | tr -d '\r'
}

# The repository's default branch (origin's HEAD), else main.
default_branch() {
  b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  b=${b#origin/}
  printf '%s' "${b:-main}"
}

# Per-checkout state (diffs, reports, reviewed heads) in <repo>/.pr-reviewer/, ignored through .git/info/exclude.
# Not inside .git: Claude Code refuses file writes there, and the session writes the report. Absolute path (in git's
# own form, C:/… on Windows), so the reviewer agent can open the files.
state_dir() {
  top=$(git rev-parse --show-toplevel) || return 1
  d="$top/.pr-reviewer"
  mkdir -p "$d"
  exclude=$(git rev-parse --git-path info/exclude)
  grep -qx '/.pr-reviewer/' "$exclude" 2>/dev/null || {
    mkdir -p "$(dirname "$exclude")"
    # A last line without a newline would otherwise swallow the pattern (and break the user's rule).
    [ -s "$exclude" ] && [ -n "$(tail -c 1 "$exclude")" ] && echo >>"$exclude"
    echo '/.pr-reviewer/' >>"$exclude"
  }
  printf '%s' "$d"
}

# pr-reviewer commit status: status <sha> <pending|success|error|failure> <description> [url].
# Best effort: without permission to write statuses the review still runs and posts.
status() {
  gh api "repos/{owner}/{repo}/statuses/$1" -f state="$2" -f context=pr-reviewer \
    -f description="$3" ${4:+-f target_url="$4"} >/dev/null 2>&1 || true
}

# Whether a shell command pushes a branch or opens a pull request (the after-push trigger).
is_push_command() {
  printf ' %s ' "$1" | grep -Eq '(^|[;&|( ])(git( +-C +[^ ]+| +-c +[^ ]+)* +push|gh +pr +create)( |$)'
}

# The repository a command works in: the directory it names (`cd <dir> && …` at its start, or `git -C <dir>`), else
# the current one. A PreToolUse hook runs before the command's own `cd`, and the session's directory may be outside the
# repo (a scratch folder), so the command's own directory wins; with none and no repo here, the session's start
# directory (CLAUDE_PROJECT_DIR) is the best guess.
command_dir() {
  printf '%s' "$1" | sed -nE \
    -e 's/^[[:space:]]*cd[[:space:]]+"([^"]+)"[[:space:]]*(&&|;).*/\1/p;t' \
    -e "s/^[[:space:]]*cd[[:space:]]+'([^']+)'[[:space:]]*(&&|;).*/\1/p;t" \
    -e 's/^[[:space:]]*cd[[:space:]]+([^ ;&|]+)[[:space:]]*(&&|;).*/\1/p;t' \
    -e 's/.*git[[:space:]]+-C[[:space:]]+"([^"]+)".*/\1/p;t' \
    -e "s/.*git[[:space:]]+-C[[:space:]]+'([^']+)'.*/\\1/p;t" \
    -e 's/.*git[[:space:]]+-C[[:space:]]+([^ ;&|]+).*/\1/p' | head -n 1
}

enter_command_dir() {
  d=$(command_dir "$1")
  if [ -n "$d" ]; then
    cd "$d" 2>/dev/null || true
  elif ! git rev-parse --git-dir >/dev/null 2>&1 && [ -n "$CLAUDE_PROJECT_DIR" ]; then
    cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
  fi
}
