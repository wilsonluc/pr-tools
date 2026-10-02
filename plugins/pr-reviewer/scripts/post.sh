#!/bin/sh
# review-pr last step: post the reviewer's report as one pull request comment and finish the commit status.
#   sh post.sh <pr-number> <reviewed-sha> <report-file>
# Prints the comment URL; round=, autofix= and max-rounds= for the skill's fix loop; and "head-moved=<sha>" when the
# pull request moved on during the review. PR_REVIEWER_AUTOFIX=0 turns the fix loop off; PR_REVIEWER_MAX_ROUNDS
# (default 5) caps review rounds with findings in a row.
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
d=$(state_dir)
echo "$sha" >"$d/$pr.reviewed"
echo "$comment"

# Review rounds with findings in a row, for the skill's autofix cap. A clean review resets the count.
if grep -m1 -v '^[[:space:]]*$' "$report" | grep -qi '^no bugs found'; then
  round=0
else
  round=$(($(cat "$d/$pr.rounds" 2>/dev/null || echo 0) + 1))
fi
echo "$round" >"$d/$pr.rounds"
echo "round=$round"
[ "${PR_REVIEWER_AUTOFIX:-1}" = 0 ] && echo "autofix=off" || echo "autofix=on"
echo "max-rounds=${PR_REVIEWER_MAX_ROUNDS:-5}"

now=$(gh pr view "$pr" --json headRefOid -q .headRefOid 2>/dev/null)
[ -z "$now" ] || [ "$now" = "$sha" ] || echo "head-moved=$now"
