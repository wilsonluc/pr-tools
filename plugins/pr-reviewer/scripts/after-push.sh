#!/bin/sh
# PostToolUse (Bash, PowerShell): after a push or `gh pr create`, tell the session when the branch's open pull
# request is at a head that has not been reviewed yet. The session then runs the review-pr skill.
# Opt out: PR_REVIEWER_OFF=1.
. "$(dirname "$0")/lib.sh"

[ -z "$PR_REVIEWER_OFF" ] || exit 0
is_push_command "$(tool_command)" || exit 0
command -v gh >/dev/null 2>&1 || exit 0
# The session's current directory: where the push ran (not CLAUDE_PROJECT_DIR, the folder the session started in).
branch=$(git symbolic-ref --short HEAD 2>/dev/null) || exit 0
[ "$branch" != "$(default_branch)" ] || exit 0
want=$(git rev-parse HEAD)

# GitHub can take a moment to move the pull request's head after a push.
pr='' head='' url=''
at_head() {
  set -- $(gh pr view "$branch" --json state,number,headRefOid,url \
    -q 'select(.state=="OPEN") | "\(.number) \(.headRefOid) \(.url)"' 2>/dev/null)
  pr=$1 head=$2 url=$3
  [ -n "$pr" ] || return 0 # no open pull request for this branch: nothing to wait for
  [ "$head" = "$want" ]
}
poll "$HOOK_HEAD_WAIT" at_head || true
[ -n "$pr" ] && [ "$head" = "$want" ] || exit 0 # no open pull request at this commit (yet)
[ "$(cat "$(state_dir)/$pr.reviewed" 2>/dev/null)" != "$want" ] || exit 0

status "$want" pending "Review queued" "$url"
# In git's own form (C:/… on Windows), which every shell's cd takes.
repo=$(git rev-parse --show-toplevel | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "PR Reviewer: pull request #$pr ($url), in the repository at $repo, is now at $want, which has not been reviewed. Run the pr-reviewer:review-pr skill for #$pr there. Its reviewers run in the background, so carry on with your task meanwhile."
