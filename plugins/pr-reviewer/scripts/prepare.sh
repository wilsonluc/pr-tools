#!/bin/sh
# review-pr step 1: save a pull request's diff for the reviewer and mark its head as under review.
#   sh prepare.sh <pr-number>
# Prints key=value lines: pr, sha, base, url, title, diff, report.
. "$(dirname "$0")/lib.sh"

pr=${1:?usage: prepare.sh <pr-number>}
info=$(gh pr view "$pr" --json number,headRefOid,baseRefName,url,title,state \
  -q '"\(.number)\t\(.headRefOid)\t\(.baseRefName)\t\(.url)\t\(.state)\t\(.title)"') || exit 1
tab=$(printf '\t')
IFS=$tab read -r pr sha base url state title <<EOF
$info
EOF
[ "$state" = OPEN ] || { echo "pull request #$pr is $state, not open" >&2; exit 1; }

d=$(state_dir)
gh pr diff "$pr" >"$d/pr-$pr.diff" || exit 1
status "$sha" pending "Review in progress" "$url"

echo "pr=$pr"
echo "sha=$sha"
echo "base=$base"
echo "url=$url"
echo "title=$title"
echo "diff=$d/pr-$pr.diff"
echo "report=$d/pr-$pr.report.md"
[ "$(git rev-parse HEAD 2>/dev/null)" = "$sha" ] ||
  echo "note=the checked-out commit is not the pull request head; files read for context may differ from the diff"
