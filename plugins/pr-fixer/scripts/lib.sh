# Shared helpers for the PR Fixer scripts. POSIX sh; needs git, and gh for anything touching GitHub.

# The `command` of the tool call a hook receives as JSON on stdin (Bash and PowerShell tools).
tool_command() {
  input=$(cat)
  out=''
  command -v jq >/dev/null 2>&1 &&
    out=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -n "$out" ] || ! command -v node >/dev/null 2>&1 ||
    out=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String((JSON.parse(s).tool_input||{}).command||""))}catch(e){}})' 2>/dev/null)
  # ponytail: no working JSON parser. Take the command's string out of the raw JSON and unescape it (\n stays a line
  # break, so commands still split per line); only when that fails, the whole text with JSON punctuation as spaces.
  [ -n "$out" ] || out=$(printf '%s' "$input" |
    sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
    awk '{ gsub(/\\n/, "\n"); gsub(/\\t/, " "); gsub(/\\"/, "\""); gsub(/\\\\/, "\\"); print }')
  [ -n "$out" ] || out=$(printf '%s' "$input" | tr '"{},' '    ')
  printf '%s' "$out" | tr -d '\r'
}

# The repository's default branch (origin's HEAD), else main.
default_branch() {
  b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  b=${b#origin/}
  printf '%s' "${b:-main}"
}

# Each command in a shell command line, as "<dir><TAB><command>" lines: the directory it runs in and the command with any
# `git -C <dir>` folded into that directory. Commands split at newlines and && || ; |; a `cd <dir>` moves the following ones (from
# the hook's own directory, ~ expanded). A PreToolUse hook runs before the command's own cd, and the session's
# directory may be outside the repo, so each git call is checked against the repo it runs in. A directory that is no
# repo falls back to the hook's own directory, then to the session's start directory (CLAUDE_PROJECT_DIR): a cd that
# fails, a variable such as $REPO (not expanded), or a PostToolUse hook, which already runs where the command's cd took
# it (replaying cd .. from there overshoots).
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
  # A line ending in " \" continues on the next (git push origin \ / HEAD:main is one command); a path ending in \ (a
  # PowerShell cd C:\repo\) does not.
  printf '%s\n' "$1" | awk '{ line = line $0 } sub(/[[:space:]]\\$/, " ", line) { next }
    { gsub(/&&|\|\||;|\|/, "\n", line); print line; line = "" } END { if (line != "") print line }' | {
    base=$(pwd)
    here=$base
    while IFS= read -r seg; do
      # Only lines that can matter cost a process (hooks have a timeout; a heredoc can be hundreds of lines).
      # (Words, not letters: "through" or "right" in a commit message must not cost a process per line.)
      case $seg in *git* | *"cd "* | *"gh pr"*) ;; *) continue ;; esac
      seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:](]+//; s/[[:space:])]+$//')
      [ -n "$seg" ] || continue
      case $seg in
        "cd "*)
          base=$(resolve_dir "$base" "$(first_word "${seg#cd }")")
          continue
          ;;
      esac
      dir=$base
      # Each -C in turn, relative to the one before, as git applies them (git -C a -C b: a/b).
      while :; do
        # The leftmost -C of a whole-word git, marked, then taken out: extraction and removal must pick the same one
        # (a path ending in git, -C /srv/git -C app, is no git call).
        m=$(printf '%s' "$seg" | sed -E "s/(^|[[:space:]])(git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*)[[:space:]]+-C[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)/\\1\\2 @@C@@\\4@@C@@/")
        c=$(printf '%s' "$m" | sed -nE 's/.*@@C@@(.*)@@C@@.*/\1/p')
        [ -n "$c" ] || break
        dir=$(resolve_dir "$dir" "$(first_word "$c")")
        next=$(printf '%s' "$m" | sed -E 's/ @@C@@.*@@C@@//')
        [ "$next" != "$seg" ] || break # nothing taken out: stop rather than loop
        seg=$next
      done
      case $seg in *git* | *"gh pr"*) ;; *) continue ;; esac
      git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || dir=$here
      git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || [ -z "$CLAUDE_PROJECT_DIR" ] || dir=$CLAUDE_PROJECT_DIR
      printf '%s\t%s\n' "$dir" "$seg"
    done
  }
}
