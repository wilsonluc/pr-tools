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

# dirs <cd target> <git -C target> <command>: the directories a command names.
dirs() {
  got="$(cd_dir "$3")|$(git_c_dir "$3")"
  [ "$got" = "$1|$2" ] || { echo "FAIL dirs expected '$1|$2' got '$got': $3"; fails=$((fails + 1)); }
}
dirs '/c/repo' '' 'cd /c/repo && git push'
dirs 'C:/My Repo' '' 'cd "C:/My Repo" && git push'
dirs '/r' '' "cd '/r'; git push"
dirs '' '/c/repo' 'git -C /c/repo push -u origin feat'
dirs '' 'C:/My Repo' 'git -C "C:/My Repo" push'
dirs '/c/work' 'repo' 'cd /c/work && git -C repo push'
dirs '' '' 'git push'
dirs '' '' 'npm test && git push'

[ "$fails" = 0 ] && echo "trigger: all checks passed" || { echo "trigger: $fails failed"; exit 1; }
