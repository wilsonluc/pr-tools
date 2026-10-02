#!/bin/sh
# review-pr step 1: save what the reviewers read and, with --comment, mark the pull request's head as under review.
#   sh prepare.sh <pr-number> [--comment] [--full]
# --full reviews the whole pull request afresh: no earlier review is used, and a head already reviewed is reviewed
# again.
# Prints key=value lines: pr, sha, base, url, title, draft, bot (opened by a bot), blob (the head's files on GitHub,
# for links), diff, report, inline (where the inline comments go), and body when the pull request has a description;
# a guide line per CLAUDE.md or AGENTS.md at the root or above a changed file; reviewed=yes when this head was already
# reviewed; after an earlier review previous (that review's report) and, when the head only added the pull request's
# own commits since, since and since_diff; for each decision source fetched (.claude/review-context,
# PR_REVIEW_CONTEXT) a context line and, when known, a context_link line; and sometimes note.
. "$(dirname "$0")/lib.sh"

usage='usage: prepare.sh <pr-number> [--comment] [--full]'
pr=${1:?$usage}
shift
comment='' full=''
for flag; do
  case $flag in
  --comment) comment=--comment ;;
  --full) full=--full ;;
  *) echo "$usage" >&2; exit 2 ;;
  esac
done
tab=$(printf '\t')
local_head=$(git rev-parse HEAD 2>/dev/null)
# Right after a push GitHub can still report the old head: wait up to HEAD_WAIT seconds for it to reach the local
# commit, so the saved diff is the one just pushed. Only for a head just pushed (the push target is at local HEAD and
# GitHub's head is behind it); a branch that is ahead or behind is taken as GitHub has it at once.
pr_ready() {
  info=$(gh pr view "$pr" --json number,headRefOid,baseRefName,url,state,headRefName,isDraft,author,title \
    -q '"\(.number)\t\(.headRefOid)\t\(.baseRefName)\t\(.url)\t\(.state)\t\(.headRefName)\t\(.isDraft)\t\(.author.is_bot // false)\t\(.title)"') ||
    exit 1
  IFS=$tab read -r pr sha base url state branch draft bot title <<EOF
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
# An earlier attempt's files must never be used for this one.
rm -f "$at.report.md" "$at.inline.json" "$at.since.diff" "$at.previous.md" "$at.body.md"
gh pr diff "$pr" >"$at.diff" || exit 1
gh pr view "$pr" --json body -q .body >"$at.body.md" 2>/dev/null || rm -f "$at.body.md"
last=$(cat "$d/$pr.reviewed" 2>/dev/null)
[ -z "$full" ] || last='' # as if never reviewed
# The skill stops for a draft or a head already reviewed without posting, so neither may be marked pending.
[ "$comment" != --comment ] || [ "$draft" = true ] || [ "$last" = "$sha" ] ||
  status "$sha" pending "Review in progress" "$url"

echo "pr=$pr"
echo "sha=$sha"
echo "base=$base"
echo "url=$url"
echo "title=$title"
echo "draft=$draft"
echo "bot=$bot"
echo "blob=${url%/pull/*}/blob/$sha"
echo "diff=$at.diff"
echo "report=$at.report.md"
echo "inline=$at.inline.json"
# The description is the author's intent: data for the reviewers, in a file since it spans lines.
[ -s "$at.body.md" ] && [ -n "$(tr -d '[:space:]' <"$at.body.md")" ] && echo "body=$at.body.md"

# A later review covers only what is new: the commits since the last reviewed head, when they are all the pull
# request's own (a rebase, force push or merge gets a full review), and only with that review's report to carry its
# findings forward. The report is our own posted one (post.sh), copied for this head, never a PR comment, which anyone
# could write.
if [ -z "$full" ] && [ -s "$d/pr-$pr.previous.md" ]; then
  cp "$d/pr-$pr.previous.md" "$at.previous.md" && echo "previous=$at.previous.md"
fi
[ "$last" != "$sha" ] || echo "reviewed=yes"
if [ -s "$at.previous.md" ] && [ -n "$last" ] && [ "$last" != "$sha" ] &&
  [ "$(gh api "repos/{owner}/{repo}/compare/$last...$sha" -q 'if .status == "ahead" and (.commits | length) == .total_commits and all(.commits[]; (.parents | length) == 1) then "ahead" else "" end' 2>/dev/null)" = ahead ] &&
  gh api -H 'Accept: application/vnd.github.v3.diff' "repos/{owner}/{repo}/compare/$last...$sha" \
    >"$at.since.diff" 2>/dev/null && [ -s "$at.since.diff" ]; then
  echo "since=$last"
  echo "since_diff=$at.since.diff"
fi

# The guidelines in this repository that cover the changed files.
gh pr diff "$pr" --name-only 2>/dev/null | guide_files "$(git rev-parse --show-toplevel)" | sed 's/^/guide=/'

# The decisions the change must respect, from other repositories (see context_sources).
context_sources | while IFS= read -r source; do
  if fetch_context "$source" "$d"; then
    echo "context=$ctx_dir"
    [ -z "$ctx_link" ] || echo "context_link=$ctx_link"
  else
    echo "note=could not fetch review context $source (gh access, the ref or the path); review without it"
  fi
done

[ "$(git rev-parse HEAD 2>/dev/null)" = "$sha" ] ||
  echo "note=the checked-out commit is not the pull request head; files read for context may differ from the diff"
