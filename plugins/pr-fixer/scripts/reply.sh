#!/bin/sh
# fix-pr: answer one review conversation, and resolve it when the finding was addressed.
#   sh reply.sh <pr-number> <thread id> <comment id> <resolve|open> <reply-file>
# The ids are the thread= and comment= values from threads.sh. With "resolve" the conversation is marked resolved
# after the reply; with "open" it stays open for the reviewer or the user. Fails when the reply cannot be posted;
# a reply posted but not resolved prints a note.

pr=${1:?usage: reply.sh <pr> <thread> <comment> <resolve|open> <reply-file>} thread=${2:?} comment=${3:?}
mode=${4:?} file=${5:?}
case $mode in resolve | open) ;; *) echo "reply.sh: mode must be resolve or open, not '$mode'" >&2; exit 2 ;; esac
[ -s "$file" ] || { echo "reply.sh: no reply text at $file" >&2; exit 1; }

gh api -X POST "repos/{owner}/{repo}/pulls/$pr/comments/$comment/replies" -F body=@"$file" -q .html_url || exit 1
[ "$mode" = resolve ] || exit 0
gh api graphql -F id="$thread" -f query='
  mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }' >/dev/null 2>&1 ||
  echo "note=replied, but could not resolve the conversation (it needs write access to the repository)"
