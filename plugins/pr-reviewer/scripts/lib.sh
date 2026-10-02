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
  printf ' %s ' "$1" |
    grep -Eq '(^|[;&|( ])(git( +-C +("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ]+)| +-c +[^ ]+)* +push|gh +pr +create)( |$)'
}

# Each command in a shell command line, as "<dir><TAB><command>" lines: the directory it runs in and the command with any
# `git -C <dir>` folded into that directory. Commands split at newlines and && || ; |; a `cd <dir>` moves the following ones (from
# the hook's own directory, ~ expanded). A PreToolUse hook runs before the command's own cd, and the session's
# directory may be outside the repo, so each git call is checked against the repo it runs in. A directory that is no
# repo (a cd that fails, a variable such as $REPO, which is not expanded) falls back to the session's start directory
# (CLAUDE_PROJECT_DIR).
first_word() {
  printf '%s' "$1" | sed -nE \
    -e 's/^[[:space:]]*"([^"]*)".*/\1/p;t' \
    -e "s/^[[:space:]]*'([^']*)'.*/\\1/p;t" \
    -e 's/^[[:space:]]*([^[:space:]]+).*/\1/p'
}
# The directory <dir> names from <base>, or <base> when it cannot be entered.
resolve_dir() {
  d=$2
  case $d in "~"*) d=$HOME${d#\~} ;; esac
  (cd "$1" 2>/dev/null && cd "$d" 2>/dev/null && pwd) || printf '%s' "$1"
}
git_commands() {
  printf '%s\n' "$1" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }' | {
    base=$(pwd)
    while IFS= read -r seg; do
      seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:](]+//; s/[[:space:])]+$//')
      [ -n "$seg" ] || continue
      case $seg in
        "cd "*)
          base=$(resolve_dir "$base" "$(first_word "${seg#cd }")")
          continue
          ;;
      esac
      dir=$base
      c=$(printf '%s' "$seg" | sed -nE "s/.*git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+-C[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+).*/\\2/p")
      if [ -n "$c" ]; then
        dir=$(resolve_dir "$base" "$(first_word "$c")")
        seg=$(printf '%s' "$seg" | sed -E "s/(git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*)[[:space:]]+-C[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)/\\1/")
      fi
      git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || [ -z "$CLAUDE_PROJECT_DIR" ] || dir=$CLAUDE_PROJECT_DIR
      printf '%s\t%s\n' "$dir" "$seg"
    done
  }
}
