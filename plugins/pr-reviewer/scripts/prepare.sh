#!/bin/sh
# review-pr step 1: save a pull request's diff for the reviewer and mark its head as under review.
#   sh prepare.sh <pr-number>
# Prints key=value lines: pr, sha, base, url, title, diff, report, and after an earlier review of this pull request
# previous (its posted report) and, when the head moved on from it by new commits only, since and since_diff.
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
# A later review covers only what is new: the commits since the last reviewed head, when they extend it (a rebase or
# force push gets a full review). The previous report is our own posted one (post.sh), never a PR comment, which
# anyone could write.
[ -s "$d/pr-$pr.previous.md" ] && echo "previous=$d/pr-$pr.previous.md"
last=$(cat "$d/$pr.reviewed" 2>/dev/null)
rm -f "$d/pr-$pr.since.diff"
if [ -n "$last" ] && [ "$last" != "$sha" ] &&
  [ "$(gh api "repos/{owner}/{repo}/compare/$last...$sha" -q .status 2>/dev/null)" = ahead ] &&
  gh api -H 'Accept: application/vnd.github.v3.diff' "repos/{owner}/{repo}/compare/$last...$sha" \
    >"$d/pr-$pr.since.diff" 2>/dev/null && [ -s "$d/pr-$pr.since.diff" ]; then
  echo "since=$last"
  echo "since_diff=$d/pr-$pr.since.diff"
fi
[ "$(git rev-parse HEAD 2>/dev/null)" = "$sha" ] ||
  echo "note=the checked-out commit is not the pull request head; files read for context may differ from the diff"
