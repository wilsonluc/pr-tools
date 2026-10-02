#!/bin/sh
# Checks for scripts/guard.sh, in a throwaway repo:
#   sh plugins/pr-fixer/tests/guard.test.sh
here=$(cd "$(dirname "$0")" && pwd)
guard="$here/../scripts/guard.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
export CLAUDE_PROJECT_DIR="$repo"
fails=0

# run <expected exit> <branch> <command>
run() {
  git -C "$repo" switch -q "$2" 2>/dev/null || git -C "$repo" switch -q -c "$2"
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$3")
  printf '%s' "$json" | sh "$guard" 2>/dev/null
  got=$?
  if [ "$got" != "$1" ]; then
    echo "FAIL ($2) expected $1 got $got: $3"
    fails=$((fails + 1))
  fi
}

run 0 feat 'git push -u origin feat'
run 0 feat 'git push'
run 0 feat 'git commit -m fix'
run 0 feat 'gh pr create --fill'
run 0 feat 'git push origin feat-main'
run 0 feat 'git log --oneline main..feat'
run 2 feat 'git push origin main'
run 2 feat 'git push origin HEAD:main'
run 2 feat 'git push origin feat:refs/heads/main'
run 2 feat 'git push --force'
run 2 feat 'git push -f origin feat'
run 2 feat 'git push --force-with-lease origin feat'
run 2 feat 'git push origin +feat'
run 2 feat 'git commit --no-verify -m x'
run 2 feat 'git commit -nm x'
run 2 feat 'git -c core.hooksPath=/dev/null commit -m x'
run 2 feat 'git config core.hooksPath .hooks'
run 2 feat 'cd sub && git push origin main'
run 2 main 'git commit -m x'
run 2 main 'git push'
run 0 main 'git switch -c feat2'
run 0 main 'git pull'

[ "$fails" = 0 ] && echo "guard: all checks passed" || { echo "guard: $fails failed"; exit 1; }
