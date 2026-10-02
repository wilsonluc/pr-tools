#!/bin/sh
# Checks for scripts/guard.sh, in a throwaway repo:
#   sh plugins/pr-fixer/tests/guard.test.sh
here=$(cd "$(dirname "$0")" && pwd)
guard="$here/../scripts/guard.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cd "$repo" || exit 1
export CLAUDE_PROJECT_DIR="$HOME" # where a session started; the guard must not prefer it to the command's repo
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

# From outside the repo: the command's own directory decides (review of pr-tools #3).
outside() {
  git -C "$repo" switch -q "$2" 2>/dev/null || git -C "$repo" switch -q -c "$2"
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$3")
  (cd / && printf '%s' "$json" | sh "$guard" 2>/dev/null)
  got=$?
  if [ "$got" != "$1" ]; then
    echo "FAIL (outside, $2) expected $1 got $got: $3"
    fails=$((fails + 1))
  fi
}
outside 2 main "git -C $repo commit -m x"
outside 2 main "cd $repo && git push"
outside 0 feat "git -C $repo commit -m x"
outside 0 feat "cd $repo && git push"
outside 2 main "cd $(dirname "$repo") && git -C $(basename "$repo") commit -m x"
# A directory that does not exist (or a variable, not expanded): the session's start directory decides.
export CLAUDE_PROJECT_DIR="$repo"
outside 2 main "cd /nonexistent/dir && git commit -m x"
outside 2 main "cd ~/../../nowhere && git commit -m x"
outside 2 main 'cd $REPO && git commit -m x'
export CLAUDE_PROJECT_DIR="$HOME" # back to a start directory that is no repo, for the tests below

# Mixed commands: each git call is checked against its own repo. A second repo, with a space in its path, on a branch.
other="$(mktemp -d)/my lib"
mkdir -p "$other"
git -C "$other" init -q -b feat
git -C "$other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
run 2 main "git commit -m x && git -C '$other' status"
run 2 main "git -C '$other' status; git push"
run 0 main "git -C '$other' commit -m x"
outside 2 feat "git -C '$repo' status && cd '$other' && git status && cd '$repo' && git push origin main"
git -C "$other" switch -q -c main
run 2 feat "git -C '$other' push"
run 2 feat "git -C '$other' push origin main"
run 2 feat "git -C '$other' commit -m x"
run 0 feat "git commit -m x && git -C '$other' status"
rm -rf "$(dirname "$other")"

# Several lines in one call: a cd line moves the lines after it (review of pr-tools #3).
outside 2 main "cd $repo\\ngit commit -m x"
outside 2 main "cd $repo\\ngit status\\ngit push"
outside 0 feat "cd $repo\\ngit commit -m x\\ngit push"
# Several -C, each relative to the one before (review of pr-tools #3).
outside 2 main "git -C $(dirname "$repo") -C $(basename "$repo") commit -m x"
outside 2 feat "git -C / -C $repo push origin main"
outside 0 feat "git -C $(dirname "$repo") -C $(basename "$repo") commit -m x"
# A backslash continues the line: still one push (review of pr-tools #3).
run 2 feat "git push origin \\\\\\nHEAD:main"
run 0 feat "git push origin \\\\\\nfeat"

[ "$fails" = 0 ] && echo "guard: all checks passed" || { echo "guard: $fails failed"; exit 1; }
