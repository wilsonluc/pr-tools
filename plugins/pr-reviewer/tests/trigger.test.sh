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
mkdir -p "$root/a" "$root/b c"
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
calls 'R ~ git push origin  HEAD:main' "$(printf 'git push origin \\\nHEAD:main')"

[ "$fails" = 0 ] && echo "trigger: all checks passed" || { echo "trigger: $fails failed"; exit 1; }
