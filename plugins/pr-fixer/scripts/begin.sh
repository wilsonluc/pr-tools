#!/bin/sh
# fix-pr step 1: check the checkout is the pull request's branch, and count fix rounds.
#   sh begin.sh <pr-number>
# Prints key=value lines: pr, branch, base, head, url, round, max-rounds, and ok=yes or ok=no with a reason.
# A round is one `fix: address review of #<pr>` commit; the round about to start is 1 + the run of such commits at
# the tip of the branch, so any other commit (the user's own work) starts the count again.
# No cap unless PR_FIXER_MAX_ROUNDS is set.

pr=${1:?usage: begin.sh <pr-number>}
info=$(gh pr view "$pr" --json headRefName,baseRefName,headRefOid,url,state \
  -q '"\(.headRefName)\t\(.baseRefName)\t\(.headRefOid)\t\(.url)\t\(.state)"') || exit 1
tab=$(printf '\t')
IFS=$tab read -r branch base head url state <<EOF
$info
EOF
max=${PR_FIXER_MAX_ROUNDS:-none}
# awk stops reading at the first other commit, so git log ends early however long the branch is.
round=$(($(git log --format=%s HEAD 2>/dev/null | awk -v p="fix: address review of #$pr" \
  'index($0, p) == 1 { n++; next } { exit } END { print n + 0 }') + 1))

echo "pr=$pr"
echo "branch=$branch"
echo "base=$base"
echo "head=$head"
echo "url=$url"
echo "round=$round"
echo "max-rounds=$max"

current=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ "$state" != OPEN ]; then
  echo "ok=no the pull request is $state"
elif [ "$current" != "$branch" ]; then
  echo "ok=no the checkout is on '$current', not the pull request's branch '$branch'"
elif [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ok=no the working tree has uncommitted changes"
elif [ "$(git rev-parse HEAD)" != "$head" ]; then
  echo "ok=no the local branch is not at the pull request's head $head (pull or push first)"
elif [ "$max" != none ] && [ "$round" -gt "$max" ]; then
  echo "ok=no $max fix rounds in a row already; the reviews keep finding issues"
else
  echo "ok=yes"
fi
