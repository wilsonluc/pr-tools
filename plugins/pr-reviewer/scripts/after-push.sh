#!/bin/sh
# PostToolUse (Bash, PowerShell): after a push or `gh pr create`, tell the session when the branch's open pull
# request is at a head that has not been reviewed yet. The session then runs the review-pr skill.
# Opt out: PR_REVIEWER_OFF=1.
. "$(dirname "$0")/lib.sh"

[ -z "$PR_REVIEWER_OFF" ] || exit 0
raw=$(tool_command | tr '\t' ' ')
cmd=$(printf '%s' "$raw" | tr '\n' ' ')
is_push_command "$cmd" || exit 0
command -v gh >/dev/null 2>&1 || exit 0
# The repo the push ran in (see git_commands): not simply CLAUDE_PROJECT_DIR, which is where the session started and
# can be a parent folder.
tab=$(printf '\t')
dir=''
while IFS=$tab read -r d seg; do
  if is_push_command "$seg"; then dir=$d; break; fi
done <<EOF
$(git_commands "$raw")
EOF
[ -n "$dir" ] && cd "$dir" 2>/dev/null || exit 0
branch=$(git symbolic-ref --short HEAD 2>/dev/null) || exit 0
[ "$branch" != "$(default_branch)" ] || exit 0
want=$(git rev-parse HEAD)

# GitHub can take a moment to move the pull request's head after a push.
pr='' head='' url=''
for i in 1 2 3 4 5 6; do
  [ "$i" = 1 ] || sleep 2
  set -- $(gh pr view "$branch" --json state,number,headRefOid,url \
    -q 'select(.state=="OPEN") | "\(.number) \(.headRefOid) \(.url)"' 2>/dev/null)
  pr=$1 head=$2 url=$3
  [ "$head" = "$want" ] && break
done
[ -n "$pr" ] && [ "$head" = "$want" ] || exit 0 # no open pull request at this commit (yet)
[ "$(cat "$(state_dir)/$pr.reviewed" 2>/dev/null)" != "$want" ] || exit 0

status "$want" pending "Review queued" "$url"
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "PR Reviewer: pull request #$pr ($url) is now at $want, which has not been reviewed. Run the pr-reviewer:review-pr skill for #$pr. Its reviewer runs in the background, so carry on with your task meanwhile."
