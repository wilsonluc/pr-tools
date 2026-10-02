#!/bin/sh
# fix-pr: the pull request's open review conversations (inline comment threads), one per line:
#   sh threads.sh <pr-number>
# thread=<id> comment=<first comment id> at=<path>:<line> by=<login> outdated=<true|false> text=<first comment,
# on one line, cut at 300 characters>, separated by tabs. Read a full comment with
# gh api repos/{owner}/{repo}/pulls/comments/<comment id>.
# ponytail: the first 100 threads only; page through reviewThreads if pull requests ever get more.

pr=${1:?usage: threads.sh <pr-number>}
gh api graphql -F n="$pr" -F owner='{owner}' -F repo='{repo}' -f query='
  query($owner: String!, $repo: String!, $n: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $n) {
        reviewThreads(first: 100) {
          nodes { id isResolved isOutdated
            comments(first: 1) { nodes { databaseId path line originalLine author { login } body } } }
        }
      }
    }
  }' -q '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | .comments.nodes[0] as $c |
  "thread=\(.id)\tcomment=\($c.databaseId)\tat=\($c.path):\($c.line // $c.originalLine)\tby=\($c.author.login)\toutdated=\(.isOutdated)\ttext=\($c.body | gsub("[\n\r\t ]+"; " ") | .[0:300])"'
