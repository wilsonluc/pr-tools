# Shared helpers for the PR Fixer scripts. POSIX sh; needs git, and gh for anything touching GitHub.

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

# The repository a command works in. A PreToolUse hook runs before the command's own `cd`, and the session's directory
# may be outside the repo (a scratch folder), so the command's directories win: a leading `cd <dir> &&`, then a
# `git -C <dir>` (relative to it). When that is no repo, the session's start directory (CLAUDE_PROJECT_DIR) is the best
# guess. Directories are taken as written, `~` expanded; variables are not ($REPO falls back).
cd_dir() {
  printf '%s' "$1" | sed -nE \
    -e 's/^[[:space:]]*cd[[:space:]]+"([^"]+)"[[:space:]]*(&&|;).*/\1/p;t' \
    -e "s/^[[:space:]]*cd[[:space:]]+'([^']+)'[[:space:]]*(&&|;).*/\\1/p;t" \
    -e 's/^[[:space:]]*cd[[:space:]]+([^ ;&|]+)[[:space:]]*(&&|;).*/\1/p' | head -n 1
}
git_c_dir() {
  printf '%s' "$1" | sed -nE \
    -e 's/.*git[[:space:]]+-C[[:space:]]+"([^"]+)".*/\1/p;t' \
    -e "s/.*git[[:space:]]+-C[[:space:]]+'([^']+)'.*/\\1/p;t" \
    -e 's/.*git[[:space:]]+-C[[:space:]]+([^ ;&|]+).*/\1/p' | head -n 1
}
enter_dir() {
  [ -n "$1" ] || return 0
  case $1 in "~"*) set -- "$HOME${1#\~}" ;; esac
  cd "$1" 2>/dev/null || true
}
enter_command_dir() {
  enter_dir "$(cd_dir "$1")"
  enter_dir "$(git_c_dir "$1")"
  git rev-parse --git-dir >/dev/null 2>&1 || [ -z "$CLAUDE_PROJECT_DIR" ] || cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
}
