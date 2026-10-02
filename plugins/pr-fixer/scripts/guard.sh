#!/bin/sh
# PreToolUse (Bash, PowerShell): refuse git commands that bypass the pull request flow, so the fix loop (and anything
# else Claude runs) never pushes to the default branch, force-pushes or skips hooks.
# Exit 2 blocks the tool call; stderr is shown to Claude as the reason.
. "$(dirname "$0")/lib.sh"

cmd=$(tool_command | tr '\n\t' '  ')
[ -n "$cmd" ] || exit 0
# Runs in the session's current directory (the repo Claude is working in). Not CLAUDE_PROJECT_DIR: that is where the
# session started, which can be a parent folder.
main=$(default_branch)
current=$(git symbolic-ref --short HEAD 2>/dev/null)

block() {
  echo "PR Fixer blocked this: $1" >&2
  exit 2
}
has() { printf ' %s ' "$cmd" | grep -Eq -- "$1"; }

GIT='git( +-C +[^ ]+| +-c +[^ ]+)*'
has '--no-verify' && block "--no-verify skips the repository's hooks."
has "$GIT +commit( +[^ ]+)* +-[a-zA-Z]*n[a-zA-Z]*( |$)" && block "git commit -n skips the repository's hooks."
has 'core\.hooksPath' && block "changing core.hooksPath turns the repository's hooks off."
has "$GIT +push( +[^ ]+)* +(--force|--force-with-lease|-f)( |=|$)" && block "force-pushing rewrites shared history; ask the user to do it."
has "$GIT +push( +[^ ]+)* +\+" && block "a + refspec force-pushes; ask the user to do it."
has "$GIT +push( +[^ ]+)* +([^ ]*:)?(refs/heads/)?$main( |$)" && block "pushing to $main; push a branch and open a pull request."
[ "$current" = "$main" ] && has "$GIT +push( |$)" && block "you are on $main; create a branch (git switch -c <name>) and push that."
[ "$current" = "$main" ] && has "$GIT +commit( |$)" && block "committing on $main; create a branch (git switch -c <name>) first."
exit 0
