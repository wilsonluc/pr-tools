#!/bin/sh
# review-pr step 1: save what the reviewers read, and mark the pull request's head as under review.
#   sh prepare.sh <pr-number>
# Prints key=value lines: pr, sha, base, url, title, diff, report; after an earlier review previous (that review's
# report) and, when the head only added the pull request's own commits since, since and since_diff; one context line
# per decision source fetched (.claude/review-context, PR_REVIEW_CONTEXT); and sometimes note.
. "$(dirname "$0")/lib.sh"

pr=${1:?usage: prepare.sh <pr-number>}
tab=$(printf '\t')
local_head=$(git rev-parse HEAD 2>/dev/null)
# Right after a push GitHub can still report the old head: wait up to HEAD_WAIT seconds for it to reach the local
# commit, so the saved diff is the one just pushed. Only for a head just pushed (the push target is at local HEAD and
# GitHub's head is behind it); a branch that is ahead or behind is taken as GitHub has it at once.
pr_ready() {
  info=$(gh pr view "$pr" --json number,headRefOid,baseRefName,url,state,headRefName,title \
    -q '"\(.number)\t\(.headRefOid)\t\(.baseRefName)\t\(.url)\t\(.state)\t\(.headRefName)\t\(.title)"') || exit 1
  IFS=$tab read -r pr sha base url state branch title <<EOF
$info
EOF
  ! { [ "$branch" = "$(git symbolic-ref --short HEAD 2>/dev/null)" ] && [ "$sha" != "$local_head" ] &&
    [ "$(git rev-parse '@{push}' 2>/dev/null)" = "$local_head" ] &&
    git merge-base --is-ancestor "$sha" "$local_head" 2>/dev/null; }
}
poll "$HEAD_WAIT" pr_ready || true
[ "$state" = OPEN ] || { echo "pull request #$pr is $state, not open" >&2; exit 1; }

d=$(state_dir)
# Files per head, so a review of an older head still running is never overwritten; post.sh removes them.
at="$d/pr-$pr-$sha"
rm -f "$at.report.md" "$at.since.diff" "$at.previous.md" # an earlier attempt's report must never be posted
gh pr diff "$pr" >"$at.diff" || exit 1
status "$sha" pending "Review in progress" "$url"

echo "pr=$pr"
echo "sha=$sha"
echo "base=$base"
echo "url=$url"
echo "title=$title"
echo "diff=$at.diff"
echo "report=$at.report.md"

# A later review covers only what is new: the commits since the last reviewed head, when they are all the pull
# request's own (a rebase, force push or merge gets a full review), and only with that review's report to carry its
# findings forward. The report is our own posted one (post.sh), copied for this head, never a PR comment, which anyone
# could write.
if [ -s "$d/pr-$pr.previous.md" ]; then
  cp "$d/pr-$pr.previous.md" "$at.previous.md" && echo "previous=$at.previous.md"
fi
last=$(cat "$d/$pr.reviewed" 2>/dev/null)
if [ -s "$at.previous.md" ] && [ -n "$last" ] && [ "$last" != "$sha" ] &&
  [ "$(gh api "repos/{owner}/{repo}/compare/$last...$sha" -q 'if .status == "ahead" and (.commits | length) == .total_commits and all(.commits[]; (.parents | length) == 1) then "ahead" else "" end' 2>/dev/null)" = ahead ] &&
  gh api -H 'Accept: application/vnd.github.v3.diff' "repos/{owner}/{repo}/compare/$last...$sha" \
    >"$at.since.diff" 2>/dev/null && [ -s "$at.since.diff" ]; then
  echo "since=$last"
  echo "since_diff=$at.since.diff"
fi

# The decisions the change must respect, from other repositories (see context_sources).
context_sources | while IFS= read -r source; do
  if where=$(fetch_context "$source" "$d"); then
    echo "context=$where"
  else
    echo "note=could not fetch review context $source (gh access, the ref or the path); review without it"
  fi
done

[ "$(git rev-parse HEAD 2>/dev/null)" = "$sha" ] ||
  echo "note=the checked-out commit is not the pull request head; files read for context may differ from the diff"
