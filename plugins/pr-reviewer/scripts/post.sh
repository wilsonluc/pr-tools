#!/bin/sh
# review-pr last step: post the review as one pull request comment, its inline comments as one pull request review,
# and finish the commit status.
#   sh post.sh <pr-number> <reviewed-sha> <report-file> [<inline-review.json>]
#   sh post.sh <pr-number> <sha> --skip <reason>     (triage skipped the review: finish the status only)
# Prints the comment URL, a note when the inline comments could not be posted, and "head-moved=<sha>" when the pull
# request moved on during the review.
. "$(dirname "$0")/lib.sh"

pr=${1:?usage: post.sh <pr> <sha> <report> [<inline>]} sha=${2:?} report=${3:?} inline=${4:-}
url=$(gh pr view "$pr" --json url -q .url 2>/dev/null)
d=$(state_dir)
at="$d/pr-$pr-$sha"
if [ "$report" = --skip ]; then
  # A status description holds at most 140 characters.
  status "$sha" success "$(printf 'Review skipped: %s' "$inline" | cut -c 1-140)" "$url"
  rm -f "$at.diff" "$at.since.diff" "$at.previous.md" "$at.body.md" "$at.issues.md" "$at.report.md" "$at.inline.json"
  exit 0
fi
if [ ! -s "$report" ]; then
  status "$sha" error "Review produced no report" "$url"
  echo "no report at $report" >&2
  exit 1
fi
comment=$({ printf '### PR Reviewer at %s\n\n' "$sha"; cat "$report"; } | gh pr comment "$pr" --body-file -) || {
  status "$sha" error "Could not post the review" "$url"
  exit 1
}
# Inline comments are a copy of the report's findings at their lines; if GitHub refuses them (a line outside the
# diff, say), the report comment still holds every finding.
if [ -n "$inline" ] && [ -s "$inline" ]; then
  gh api -X POST "repos/{owner}/{repo}/pulls/$pr/reviews" --input "$inline" >/dev/null 2>&1 ||
    echo "note=the inline comments were not posted; the review comment has every finding"
fi
status "$sha" success "Review posted" "$comment"
# The next review starts from this one: its report (to check the findings) and its head (to review only what is
# new). The head only once the report is kept, so the two always belong together.
cp "$report" "$d/pr-$pr.previous.md" && echo "$sha" >"$d/$pr.reviewed"
rm -f "$at.diff" "$at.since.diff" "$at.previous.md" "$at.body.md" "$at.issues.md" "$at.report.md" "$at.inline.json"
echo "$comment"

now=$(gh pr view "$pr" --json headRefOid -q .headRefOid 2>/dev/null)
[ -z "$now" ] || [ "$now" = "$sha" ] || echo "head-moved=$now"
