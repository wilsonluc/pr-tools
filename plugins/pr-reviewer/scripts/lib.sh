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
  # so words like `push` still end at a space for the pattern.
  [ -n "$out" ] || out=$(printf '%s' "$input" | tr '"{},' '    ')
  printf '%s' "$out" | tr -d '\r'
}

# Whether a shell command pushes a branch or opens a pull request (the after-push trigger). Best effort: a push
# written another way just gets no automatic review (run /pr-reviewer:review-pr).
is_push_command() {
  printf ' %s ' "$1" | tr '\n' ' ' | grep -Eq '(^|[;&|( ])(git( +-[cC] +[^ ]+)* +push|gh +pr +create)( |$)'
}

# The repository's default branch (origin's HEAD), else main.
default_branch() {
  b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  b=${b#origin/}
  printf '%s' "${b:-main}"
}

# How long to wait for GitHub to report a pushed head, in seconds, and how often to look. The after-push hook waits
# less than prepare.sh: it must end within its own timeout (30 s, in plugin.json).
HEAD_WAIT=${PR_REVIEWER_HEAD_WAIT:-20}
HOOK_HEAD_WAIT=10
POLL=2

# poll <seconds> <check> [args]: run the check until it succeeds or the time is up, every POLL seconds. Runs in this
# shell, so the variables the check sets are kept; fails when the time ran out.
poll() {
  until_s=$(($(date +%s) + $1))
  shift
  until "$@"; do
    [ "$(date +%s)" -lt "$until_s" ] || return 1
    sleep "$POLL"
  done
}

# Per-checkout state (diffs, reports, reviewed heads, fetched context) in <repo>/.pr-reviewer/, ignored through
# .git/info/exclude. Not inside .git: Claude Code refuses file writes there, and the session writes the report.
# Absolute path (in git's own form, C:/… on Windows), so the reviewer agents can open the files.
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

# The decision sources the review must weigh, one per line, as owner/repo[@ref][:path]: the lines of the repository's
# .claude/review-context (# starts a comment), then PR_REVIEW_CONTEXT (separated by spaces or commas).
context_sources() {
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  {
    [ -f "$top/.claude/review-context" ] && sed 's/#.*//' "$top/.claude/review-context"
    printf '%s\n' "${PR_REVIEW_CONTEXT:-}" | tr ', ' '\n\n'
  } | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -E '^[^/[:space:]]+/[^/[:space:]@:]+' | awk '!seen[$0]++'
}

# fetch_context <owner/repo[@ref][:path]> <state dir>: a shallow, up-to-date copy of that repository under
# <state dir>/context/, printing the directory to read (the path inside it, when given). Fails when it cannot fetch.
fetch_context() {
  spec=$1
  path=''
  case $spec in *:*) path=${spec#*:} spec=${spec%%:*} ;; esac
  ref=''
  case $spec in *@*) ref=${spec#*@} spec=${spec%%@*} ;; esac
  # One copy per repository and ref, so two lines naming the same repository at different refs never share one.
  dir="$2/context/$(printf '%s' "$spec${ref:+@$ref}" | tr '/@' '__')"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch -q --depth 1 origin "${ref:-HEAD}" && git -C "$dir" reset -q --hard FETCH_HEAD || return 1
  else
    rm -rf "$dir"
    gh repo clone "$spec" "$dir" -- -q --depth 1 ${ref:+--branch "$ref"} >/dev/null 2>&1 || return 1
  fi
  [ -e "$dir/$path" ] || return 1
  printf '%s' "$dir${path:+/$path}"
}
