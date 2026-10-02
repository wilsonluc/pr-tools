#!/bin/sh
# PostToolUse (Bash, PowerShell): after a push or `gh pr create`, tell the session when a branch's open pull request
# is at a head that has not been reviewed yet. The session then runs the review-pr skill.
# Opt out: PR_REVIEWER_OFF=1.
. "$(dirname "$0")/lib.sh"

[ -z "$PR_REVIEWER_OFF" ] || exit 0
raw=$(tool_command | tr '\t' ' ')
is_push_command "$(command_lines "$raw")" || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# Every repository the command can touch (command_repos): each on a branch with an open pull request at its HEAD gets
# a review. One deadline for all, inside the hook's own timeout.
until_all=$(($(date +%s) + HOOK_HEAD_WAIT))
messages=''
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  cd "$repo" 2>/dev/null || continue
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || continue
  [ "$branch" != "$(default_branch)" ] || continue
  want=$(git rev-parse HEAD)
  pr='' head='' url=''
  at_head() {
    set -- $(gh pr view "$branch" --json state,number,headRefOid,url \
      -q 'select(.state=="OPEN") | "\(.number) \(.headRefOid) \(.url)"' 2>/dev/null)
    pr=$1 head=$2 url=$3
    [ -n "$pr" ] || return 0 # no open pull request for this branch: nothing to wait for
    [ "$head" = "$want" ]
  }
  # GitHub can take a moment to move the pull request's head after a push.
  left=$((until_all - $(date +%s)))
  poll "$((left > 0 ? left : 0))" at_head || true
  [ -n "$pr" ] && [ "$head" = "$want" ] || continue # no open pull request at this commit (yet)
  [ "$(cat "$(state_dir)/$pr.reviewed" 2>/dev/null)" != "$want" ] || continue
  status "$want" pending "Review queued" "$url"
  # The repository can differ from the session's directory: the skill runs its scripts there. In git's own form
  # (C:/… on Windows), which every shell's cd takes; an MSYS /c/… path fails in PowerShell.
  at=$(printf '%s' "$repo" | sed 's/\\/\\\\/g; s/"/\\"/g')
  messages="${messages}PR Reviewer: pull request #$pr ($url), in the repository at $at, is now at $want, which has not been reviewed. Run the pr-reviewer:review-pr skill for #$pr in that repository. "
done <<EOF
$(command_repos "$raw")
EOF
[ -n "$messages" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "${messages}Its reviewer runs in the background, so carry on with your task meanwhile."
