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
trigger 1 'git pushd'
trigger 1 'git status'
trigger 1 'gh pr view 3'
trigger 1 'echo pushed'

# dir <expected> <command>: the directory a command names (command_dir).
dir() {
  got=$(command_dir "$2")
  [ "$got" = "$1" ] || { echo "FAIL dir expected '$1' got '$got': $2"; fails=$((fails + 1)); }
}
dir '/c/repo' 'cd /c/repo && git push'
dir 'C:/My Repo' 'cd "C:/My Repo" && git push'
dir '/r' "cd '/r'; git push"
dir '/c/repo' 'git -C /c/repo push -u origin feat'
dir 'C:/My Repo' 'git -C "C:/My Repo" push'
dir '' 'git push'
dir '' 'npm test && git push'

[ "$fails" = 0 ] && echo "trigger: all checks passed" || { echo "trigger: $fails failed"; exit 1; }
