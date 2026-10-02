#!/bin/sh
# review-pr step 1: save a pull request's diff for the reviewer and mark its head as under review.
#   sh prepare.sh <pr-number>
# Prints key=value lines: pr, sha, base, url, title, diff, report.
. "$(dirname "$0")/lib.sh"

pr=${1:?usage: prepare.sh <pr-number>}
tab=$(printf '\t')
local_head=$(git rev-parse HEAD 2>/dev/null)
# Right after a push GitHub can still report the old head: wait up to ~20 s for it to reach the local commit, so the
# saved diff is the one just pushed (a pull request checked out elsewhere is taken as it is).
for i in 1 2 3 4 5 6 7 8; do
  [ "$i" = 1 ] || sleep 3
  info=$(gh pr view "$pr" --json number,headRefOid,baseRefName,url,title,state,headRefName \
    -q '"\(.number)\t\(.headRefOid)\t\(.baseRefName)\t\(.url)\t\(.state)\t\(.headRefName)\t\(.title)"') || exit 1
  IFS=$tab read -r pr sha base url state branch title <<EOF
$info
EOF
  [ "$branch" = "$(git symbolic-ref --short HEAD 2>/dev/null)" ] && [ "$sha" != "$local_head" ] || break
done
[ "$state" = OPEN ] || { echo "pull request #$pr is $state, not open" >&2; exit 1; }

d=$(state_dir)
rm -f "$d/pr-$pr.report.md" # a previous review's report must never be posted for this head
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
