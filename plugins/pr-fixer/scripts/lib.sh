# Shared helpers for the PR Fixer scripts. POSIX sh; needs git, and gh for anything touching GitHub.
# Everything from tool_command to command_repos is the same in both plugins' lib.sh (tests check it).

# The `command` of the tool call a hook receives as JSON on stdin (Bash and PowerShell tools).
tool_command() {
  input=$(cat)
  out=''
  command -v jq >/dev/null 2>&1 &&
    out=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -n "$out" ] || ! command -v node >/dev/null 2>&1 ||
    out=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String((JSON.parse(s).tool_input||{}).command||""))}catch(e){}})' 2>/dev/null)
  # ponytail: no working JSON parser. Take the command's string out of the raw JSON and unescape it in one pass (\\
  # first, so C:\\new stays a path, not a line break); only when that fails, the whole text with JSON punctuation as
  # spaces.
  [ -n "$out" ] || out=$(printf '%s' "$input" |
    sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
    awk '{
      s = $0; o = ""
      while ((i = index(s, "\\")) > 0) {
        c = substr(s, i + 1, 1)
        if (c == "u") {
          h = tolower(substr(s, i + 2, 4)); v = 0
          for (k = 1; k <= 4; k++) v = v * 16 + index("0123456789abcdef", substr(h, k, 1)) - 1
          o = o substr(s, 1, i - 1) (v > 0 && v < 128 ? sprintf("%c", v) : "?")
          s = substr(s, i + 6)
          continue
        }
        o = o substr(s, 1, i - 1) (c == "n" ? "\n" : c == "t" ? " " : c == "r" ? "" : c)
        s = substr(s, i + 2)
      }
      print o s
    }')
  [ -n "$out" ] || out=$(printf '%s' "$input" | tr '"{},' '    ')
  printf '%s' "$out" | tr -d '\r'
}

# The repository's default branch (origin's HEAD), else main.
default_branch() {
  b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  b=${b#origin/}
  printf '%s' "${b:-main}"
}

# A command line as one command per line: a line ending in " \" (sh) or " `" (PowerShell) continues on the next, and
# lines split at && || ; |. No directory tracking: see command_repos for which repositories a command can touch.
command_lines() {
  printf '%s\n' "$1" | awk '{ line = line $0 } sub(/[[:space:]][\\`]$/, " ", line) { next }
    { gsub(/&&|\|\||;|\|/, "\n", line); print line; line = "" } END { if (line != "") print line }'
}

# An option's value or a path, as a regular expression: quoted, or a word with \-escaped spaces.
VALUE='("[^"]*"|'"'"'[^'"'"']*'"'"'|([^[:space:];&|()\\]|\\.)+\\?)'

# The directories a command names: every cd, pushd, chdir, Set-Location, sl, Push-Location and git -C target, in
# order, each as written and, when it holds an escaped space, also cut there (a PowerShell path may end in \).
# Each distinct one once, so a long message naming the same -C on every line costs nothing per line.
command_targets() {
  printf '%s\n' "$1" |
    grep -oiE "(^|[[:space:];&|(])(cd|pushd|chdir|set-location|sl|push-location)[[:space:]]+(-(literal)?path[[:space:]]+)?$VALUE|[[:space:]]-C[[:space:]]+$VALUE" |
    sed -E 's/^[[:space:];&|(]*[^[:space:]]+[[:space:]]+//; s/^-[A-Za-z]*[Pp][Aa][Tt][Hh][[:space:]]+//' |
    awk '!seen[$0]++' |
    while IFS= read -r t; do
      case $t in
        \"*\" | \'*\') t=${t#?} && printf '%s\n' "${t%?}" ;;
        *) printf '%s\n' "$t" | sed 's/\\ / /g'; printf '%s\n' "${t%%\\ *}" ;;
      esac
    done
}

# The directory <dir> names from <base> (~ expanded), or nothing when it cannot be entered.
resolve_dir() {
  d=$2
  case $d in "~"*) d=$HOME${d#\~} ;; esac
  (cd "$1" 2>/dev/null && cd "$d" 2>/dev/null && pwd)
}

# Every repository a command can touch, by top level, each once: the hook's own directory, the session's start
# directory (CLAUDE_PROJECT_DIR), and each directory the command names, taken both from the one before (cd a && cd b,
# git -C a -C b) and from the hook's directory. Neither the hook's directory nor the start directory is reliably the
# repository a command works in (a PreToolUse hook runs before the command's own cd, a PostToolUse hook after it), so
# callers check them all: the guard blocks when any is on its default branch.
command_repos() {
  here=$(pwd)
  {
    printf '%s\n' "$here"
    [ -z "$CLAUDE_PROJECT_DIR" ] || printf '%s\n' "$CLAUDE_PROJECT_DIR"
    base=$here
    command_targets "$1" | while IFS= read -r t; do
      [ -n "$t" ] || continue
      if a=$(resolve_dir "$base" "$t") && [ -n "$a" ]; then
        base=$a
        printf '%s\n' "$a"
      fi
      resolve_dir "$here" "$t"
    done
  } | while IFS= read -r d; do
    [ -n "$d" ] && git -C "$d" rev-parse --show-toplevel 2>/dev/null
  done | awk '!seen[$0]++'
}
