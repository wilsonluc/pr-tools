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

# Per-clone state (diffs, reports, reviewed heads), kept out of the work tree.
state_dir() {
  d="$(git rev-parse --git-common-dir)/pr-reviewer"
  mkdir -p "$d"
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
