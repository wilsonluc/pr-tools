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
# Files per head, so a review of an older head still running is not overwritten by this one.
at="$d/pr-$pr-$sha"
rm -f "$at.report.md" "$at.since.diff" # an earlier attempt's report must never be posted for this head
gh pr diff "$pr" >"$at.diff" || exit 1
status "$sha" pending "Review in progress" "$url"

echo "pr=$pr"
echo "sha=$sha"
echo "base=$base"
echo "url=$url"
echo "title=$title"
echo "diff=$at.diff"
echo "report=$at.report.md"
# A later review covers only what is new: the commits since the last reviewed head, when they only add the pull
# request's own commits to it. A rebase, force push or merge (of the base branch, say) gets a full review, and so does
# any head without the previous report to carry its findings forward. That report is our own posted one (post.sh),
# never a PR comment, which anyone could write.
previous="$d/pr-$pr.previous.md"
[ -s "$previous" ] && echo "previous=$previous"
last=$(cat "$d/$pr.reviewed" 2>/dev/null)
if [ -s "$previous" ] && [ -n "$last" ] && [ "$last" != "$sha" ] &&
  [ "$(gh api "repos/{owner}/{repo}/compare/$last...$sha" \
    -q 'if .status == "ahead" and all(.commits[]; (.parents | length) == 1) then "ahead" else "" end' \
    2>/dev/null)" = ahead ] &&
  gh api -H 'Accept: application/vnd.github.v3.diff' "repos/{owner}/{repo}/compare/$last...$sha" \
    >"$at.since.diff" 2>/dev/null && [ -s "$at.since.diff" ]; then
  echo "since=$last"
  echo "since_diff=$at.since.diff"
fi
[ "$(git rev-parse HEAD 2>/dev/null)" = "$sha" ] ||
  echo "note=the checked-out commit is not the pull request head; files read for context may differ from the diff"
