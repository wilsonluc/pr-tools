#!/bin/sh
# review-pr last step: post the reviewer's report as one pull request comment and finish the commit status.
#   sh post.sh <pr-number> <reviewed-sha> <report-file>
# Prints the comment URL, and "head-moved=<sha>" when the pull request moved on during the review.
. "$(dirname "$0")/lib.sh"

pr=${1:?usage: post.sh <pr> <sha> <report>} sha=${2:?} report=${3:?}
url=$(gh pr view "$pr" --json url -q .url 2>/dev/null)
if [ ! -s "$report" ]; then
  status "$sha" error "Review produced no report" "$url"
  echo "no report at $report" >&2
  exit 1
fi
comment=$({ printf '### PR Reviewer at %s\n\n' "$sha"; cat "$report"; } | gh pr comment "$pr" --body-file -) || {
  status "$sha" error "Could not post the review" "$url"
  exit 1
}
status "$sha" success "Review posted" "$comment"
echo "$sha" >"$(state_dir)/$pr.reviewed"
echo "$comment"

now=$(gh pr view "$pr" --json headRefOid -q .headRefOid 2>/dev/null)
[ -z "$now" ] || [ "$now" = "$sha" ] || echo "head-moved=$now"
