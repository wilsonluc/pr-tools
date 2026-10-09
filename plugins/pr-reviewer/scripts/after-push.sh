#!/bin/sh
# PostToolUse (Bash, PowerShell): after a push, `gh pr create` or `gh pr ready`, tell the session when the branch's open pull
# request is at a head that has not been reviewed yet. The session then runs the review-pr skill. Draft pull
# requests and ones opened by bots are left alone (run /pr-reviewer:review-pr for those).
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
  set -- $(gh pr view "$branch" --json state,isDraft,author,number,headRefOid,url \
    -q 'select(.state == "OPEN" and (.isDraft | not) and (.author.is_bot | not)) | "\(.number) \(.headRefOid) \(.url)"' \
    2>/dev/null)
  pr=$1 head=$2 url=$3
  [ -n "$pr" ] || return 0 # no open pull request to review for this branch: nothing to wait for
  [ "$head" = "$want" ]
}
poll "$HOOK_HEAD_WAIT" at_head || true
[ -n "$pr" ] && [ "$head" = "$want" ] || exit 0 # none to review at this commit (yet)
[ "$(cat "$(state_dir)/$pr.reviewed" 2>/dev/null)" != "$want" ] || exit 0

status "$want" pending "Review queued" "$url"
# In git's own form (C:/… on Windows), which every shell's cd takes.
repo=$(git rev-parse --show-toplevel | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "PR Reviewer: pull request #$pr ($url), in the repository at $repo, is now at $want, which has not been reviewed. Run the pr-reviewer:review-pr skill there with the arguments $pr --comment. Its reviewers run in the background, so carry on with your task meanwhile."
