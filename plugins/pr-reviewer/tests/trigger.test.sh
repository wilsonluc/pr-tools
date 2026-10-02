#!/bin/sh
# Checks for the after-push trigger pattern (is_push_command):
#   sh plugins/pr-reviewer/tests/trigger.test.sh
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../scripts/lib.sh"
fails=0

# trigger <expected 0|1> <command>: does after-push.sh react to it?
trigger() {
  is_push_command "$2" && got=0 || got=1
  [ "$got" = "$1" ] || { echo "FAIL trigger expected $1 got $got: $2"; fails=$((fails + 1)); }
}
trigger 0 'git push'
trigger 0 'git push -u origin feat'
trigger 0 'git -C repo push'
trigger 0 'npm test && git push'
trigger 0 'gh pr create --fill'
trigger 0 'git -C "C:/My Repo" push'
trigger 0 "git -C 'C:/My Repo' push origin feat"
trigger 1 'git pushd'
trigger 1 'git status'
trigger 1 'gh pr view 3'
trigger 1 'echo pushed'

# calls <expected lines> <command>: git_commands, with directories relative to a scratch tree (a/ and "b c"/).
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
git init -q "$root/a" && git init -q "$root/b c" # repos, so no fallback applies
calls() {
  got=$(cd "$root" && CLAUDE_PROJECT_DIR='' git_commands "$2" | sed "s|$root|R|; s|$(printf '\t')| ~ |")
  [ "$got" = "$1" ] || { echo "FAIL calls expected '$1' got '$got': $2"; fails=$((fails + 1)); }
}
calls 'R/a ~ git push' 'cd a && git push'
calls 'R/b c ~ git push' 'cd "b c" && git push'
calls 'R/a ~ git push -u origin feat' 'git -C a push -u origin feat'
calls 'R/b c ~ git push' 'git -C "b c" push'
calls "R ~ git commit -m x
R/a ~ git status" 'git commit -m x && git -C a status'
calls 'R/a ~ git push' 'cd a && npm test && git push' # lines without git, cd or gh are skipped
calls 'R ~ git push' 'cd nowhere && git push'
calls 'R/a ~ git commit -m x
R/a ~ git push' "$(printf 'cd a\ngit commit -m x\ngit push')"
# After the command (PostToolUse) the hook is already where cd .. took it: replayed, cd .. overshoots to no repo,
# so the hook's own directory is used (review of pr-tools #3).
git init -q "$root/r"
mkdir -p "$root/r/sub"
got=$(cd "$root/r" && CLAUDE_PROJECT_DIR='' git_commands 'cd .. && git push' | sed "s|$root|R|; s|$(printf '\t')| ~ |")
[ "$got" = 'R/r ~ git push' ] || { echo "FAIL post cd ..: got '$got'"; fails=$((fails + 1)); }
# A path ending in \ (PowerShell's cd C:\repo\) is no continuation: the commit stays its own call, wherever the cd
# lands (Git Bash takes a\ as a/, other shells may not).
got=$(cd "$root" && CLAUDE_PROJECT_DIR='' git_commands "$(printf 'cd a\\\ngit commit -m x')" | sed 's/.*\t//')
[ "$got" = 'git commit -m x' ] || { echo "FAIL cd path ending in \\: got '$got'"; fails=$((fails + 1)); }
mkdir -p "$root/git" && git init -q "$root/git/app"
calls 'R/git/app ~ git push' 'git -C git -C app push' # a -C path that is itself named git
calls 'R ~ git push origin HEAD:main' "$(printf 'git push origin \\\nHEAD:main')"

# tool_command without jq or node: the command's own text, unescaped (functions shadow the tools for command -v).
got=$(
  jq() { return 1; }
  node() { return 1; }
  printf '%s' '{"session_id":"s","tool_name":"Bash","tool_input":{"command":"cd /r \u0026\u0026 x\ngit commit -m \"a b\"","description":"d"}}' |
    tool_command
)
want=$(printf 'cd /r \\u0026\\u0026 x\ngit commit -m "a b"')
[ "$got" = "$want" ] || { echo "FAIL tool_command fallback: got '$got'"; fails=$((fails + 1)); }

# poll: retries until the check succeeds, keeps the variables it sets, and gives up when the time is up.
POLL=0
tries=0
third() { tries=$((tries + 1)); [ "$tries" -ge 3 ]; }
poll 5 third && [ "$tries" = 3 ] || { echo "FAIL poll: expected success on try 3, got $tries tries"; fails=$((fails + 1)); }
never() { false; }
start=$(date +%s)
if poll 1 never; then echo "FAIL poll: a check that never succeeds succeeded"; fails=$((fails + 1)); fi
[ $(($(date +%s) - start)) -le 3 ] || { echo "FAIL poll: did not stop after its time"; fails=$((fails + 1)); }

[ "$fails" = 0 ] && echo "trigger: all checks passed" || { echo "trigger: $fails failed"; exit 1; }
