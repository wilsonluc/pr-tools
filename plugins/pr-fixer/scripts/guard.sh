#!/bin/sh
# PreToolUse (Bash, PowerShell): refuse git commands that bypass the pull request flow, so the fix loop (and anything
# else Claude runs) never pushes to the default branch, force-pushes or skips hooks.
# Exit 2 blocks the tool call; stderr is shown to Claude as the reason.
. "$(dirname "$0")/lib.sh"

raw=$(tool_command | tr '\t' ' ')
[ -n "$raw" ] || exit 0
case $raw in *git*) ;; *) exit 0 ;; esac # every rule below is about a git call

block() {
  echo "PR Fixer blocked this: $1" >&2
  exit 2
}
# Patterns match one command at a time (command_lines), so a word from a neighbouring command never completes one.
lines=$(command_lines "$raw")
has() { printf '%s\n' "$lines" | sed 's/.*/ & /' | grep -Eq -- "$1"; }
GIT="[^[:alnum:]_./-]git( +-[cC] +$VALUE)*"
ANY='( +[^ ]+)*'

# Anywhere: these bypass the flow in any repository.
has '--no-verify' && block "--no-verify skips the repository's hooks."
has "$GIT +commit$ANY +-[a-zA-Z]*n[a-zA-Z]*( |$)" && block "git commit -n skips the repository's hooks."
has 'core\.hooksPath' && block "changing core.hooksPath turns the repository's hooks off."
has "$GIT +push$ANY +(--force|--force-with-lease|-f)( |=|$)" && block "force-pushing rewrites shared history; ask the user to do it."
has "$GIT +push$ANY +\+" && block "a + refspec force-pushes; ask the user to do it."

# Commits and pushes, against every repository the command can touch (command_repos): fails closed, so a command that
# also names a repository on its default branch is blocked; run it from that repository's own branch instead.
has "$GIT$ANY +(commit|push)( |$)" || exit 0
tab=$(printf '\t')
repos=$(command_repos "$raw")
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  main=$(cd "$repo" && default_branch)
  has "$GIT$ANY +push$ANY +([^ ]*:)?(refs/heads/)?$main( |$)" &&
    block "pushing to $main; push a branch and open a pull request."
  [ "$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)" = "$main" ] &&
    block "$repo is on $main, and this command commits or pushes; create a branch there (git switch -c <name>) first, or run the command from a repository on a branch."
done <<EOF
$repos
EOF
exit 0
