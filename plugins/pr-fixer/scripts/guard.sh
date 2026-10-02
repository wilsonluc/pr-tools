#!/bin/sh
# PreToolUse (Bash, PowerShell): refuse git commands that bypass the pull request flow, so the fix loop (and anything
# else Claude runs) never pushes to the default branch, force-pushes or skips hooks.
# Exit 2 blocks the tool call; stderr is shown to Claude as the reason.
. "$(dirname "$0")/lib.sh"

raw=$(tool_command | tr '\t' ' ')
cmd=$(printf '%s' "$raw" | tr '\n' ' ')
[ -n "$cmd" ] || exit 0

block() {
  echo "PR Fixer blocked this: $1" >&2
  exit 2
}
has() { printf ' %s ' "$cmd" | grep -Eq -- "$1"; }

GIT='git( +-C +("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ]+)| +-c +[^ ]+)*'
# Whatever the repository: these bypass the flow anywhere.
has '--no-verify' && block "--no-verify skips the repository's hooks."
has "$GIT +commit( +[^ ]+)* +-[a-zA-Z]*n[a-zA-Z]*( |$)" && block "git commit -n skips the repository's hooks."
has 'core\.hooksPath' && block "changing core.hooksPath turns the repository's hooks off."
has "$GIT +push( +[^ ]+)* +(--force|--force-with-lease|-f)( |=|$)" && block "force-pushing rewrites shared history; ask the user to do it."
has "$GIT +push( +[^ ]+)* +\+" && block "a + refspec force-pushes; ask the user to do it."

# Per git call, against the repository it runs in (see git_commands): its default branch and current branch. Not
# simply CLAUDE_PROJECT_DIR, which is where the session started and can be a parent folder.
tab=$(printf '\t')
calls=$(git_commands "$raw") # lines split commands too
while IFS=$tab read -r dir seg; do
  [ -n "$seg" ] || continue
  is() { printf ' %s ' "$seg" | grep -Eq -- "$1"; }
  is 'git( +-c +[^ ]+)* +(push|commit)( |$)' || continue
  main=$(cd "$dir" 2>/dev/null && default_branch)
  current=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)
  is "git( +-c +[^ ]+)* +push( +[^ ]+)* +([^ ]*:)?(refs/heads/)?$main( |$)" &&
    block "pushing to $main; push a branch and open a pull request."
  [ "$current" = "$main" ] && is 'git( +-c +[^ ]+)* +push( |$)' &&
    block "you are on $main in $dir; create a branch (git switch -c <name>) and push that."
  [ "$current" = "$main" ] && is 'git( +-c +[^ ]+)* +commit( |$)' &&
    block "committing on $main in $dir; create a branch (git switch -c <name>) first."
done <<EOF
$calls
EOF
exit 0
