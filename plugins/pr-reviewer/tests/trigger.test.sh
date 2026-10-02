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

# repos <expected repos, one per line, R = scratch root> <command> [directory to run from]: command_repos.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
for r in a "b c" "My Repo" git/app r lib app; do git init -q "$root/$r"; done
mkdir -p "$root/r/sub"
top=$(dirname "$(git -C "$root/a" rev-parse --show-toplevel)") # the root as git writes it (C:/… on Windows)
repos() {
  got=$(cd "$root/${3:-}" && CLAUDE_PROJECT_DIR='' command_repos "$2" | sed "s|^$top|R|" | sort)
  want=$(printf '%s\n' "$1" | sort)
  [ "$got" = "$want" ] || { echo "FAIL repos expected '$want' got '$got': $2"; fails=$((fails + 1)); }
}
repos 'R/a' 'cd a && git push'
repos 'R/b c' 'cd "b c" && git push'
repos 'R/a' 'git -C a push -u origin feat'
repos 'R/b c' "git -C 'b c' push"
repos 'R/a' 'git commit -m x && git -C a status'
repos 'R/git/app
R/app' 'git -C git -C app push' # chained (git/app), and app itself as well: every repository it could be
repos 'R/lib
R/app' 'cd lib && git push && cd ../app && git push'                    # every repository, not only the first
repos 'R/a' 'Set-Location a; git commit -m x'                          # PowerShell
repos 'R/a' 'sl -Path a; git push'
repos 'R/a' 'Push-Location -LiteralPath "a"; git push'
repos 'R/a' 'pushd a && git push'
repos 'R/My Repo' 'cd My\ Repo && git commit -m x'                      # an escaped space
repos 'R/My Repo' 'git -C My\ Repo push --force'
repos 'R/r' 'cd .. && git push' r/sub                                   # from the hook's directory too (PostToolUse)
repos '' 'cd nowhere && git push'
repos 'R/a' "$(printf 'cd a\ngit commit -m x')"

# command_lines: one command per line; " \" and " `" continue a line, a path ending in \ does not.
lines() {
  got=$(command_lines "$2")
  [ "$got" = "$1" ] || { echo "FAIL lines expected '$1' got '$got': $2"; fails=$((fails + 1)); }
}
lines 'git push origin HEAD:main' "$(printf 'git push origin \\\nHEAD:main')"
lines 'git push origin HEAD:main' "$(printf 'git push origin `\nHEAD:main')"
lines "cd C:\\repo\\
git commit -m x" "$(printf 'cd C:\\repo\\\ngit commit -m x')"
lines "$(printf 'a \n b\n c')" 'a && b; c'

# tool_command without jq or node: the command's own text, unescaped in one pass (functions shadow the tools for
# command -v). \\ stays a backslash, so C:\new and C:\tools stay paths.
fallback() {
  got=$(
    jq() { return 1; }
    node() { return 1; }
    printf '{"session_id":"s","tool_name":"Bash","tool_input":{"command":"%s","description":"d"}}' "$1" | tool_command
  )
  [ "$got" = "$2" ] || { echo "FAIL tool_command fallback: got '$got', want '$2'"; fails=$((fails + 1)); }
}
fallback 'cd /r \u0026\u0026 x\ngit commit -m \"a b\"' "$(printf 'cd /r && x\ngit commit -m "a b"')"
fallback 'cd C:\\tools\\new; git commit -m x' 'cd C:\tools\new; git commit -m x'
fallback 'git push origin main\r' 'git push origin main'

# poll: retries until the check succeeds, keeps the variables it sets, and gives up when the time is up.
POLL=0
tries=0
third() { tries=$((tries + 1)); [ "$tries" -ge 3 ]; }
poll 5 third && [ "$tries" = 3 ] || { echo "FAIL poll: expected success on try 3, got $tries tries"; fails=$((fails + 1)); }
never() { false; }
start=$(date +%s)
if poll 1 never; then echo "FAIL poll: a check that never succeeds succeeded"; fails=$((fails + 1)); fi
[ $(($(date +%s) - start)) -le 3 ] || { echo "FAIL poll: did not stop after its time"; fails=$((fails + 1)); }

# Both plugins carry the same command helpers (each plugin is installed on its own, so they cannot share a file).
shared() { sed -n '/^tool_command()/,/^command_repos()/p' "$1"; }
[ "$(shared "$here/../scripts/lib.sh")" = "$(shared "$here/../../pr-fixer/scripts/lib.sh")" ] ||
  { echo "FAIL the two lib.sh copies differ between tool_command and command_repos"; fails=$((fails + 1)); }

[ "$fails" = 0 ] && echo "trigger: all checks passed" || { echo "trigger: $fails failed"; exit 1; }
