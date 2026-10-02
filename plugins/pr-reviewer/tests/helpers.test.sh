#!/bin/sh
# Checks for the shell helpers (no GitHub needed):
#   sh plugins/pr-reviewer/tests/helpers.test.sh
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../scripts/lib.sh"
fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# trigger <expected 0|1> <command>: does after-push.sh react to it?
trigger() {
  is_push_command "$2" && got=0 || got=1
  [ "$got" = "$1" ] || fail "trigger expected $1 got $got: $2"
}
trigger 0 'git push'
trigger 0 'git push -u origin feat'
trigger 0 'git -C repo push'
trigger 0 'git -c http.extraHeader=x push'
trigger 0 'npm test && git push'
trigger 0 "git commit -m 'x'
git push"
trigger 0 'gh pr create --fill'
trigger 1 'git pushd'
trigger 1 'git status'
trigger 1 'gh pr view 3'
trigger 1 'echo pushed'

# poll: returns as soon as the check passes, fails once the time is up, keeps the check's variables.
POLL=0
n=0
count() { n=$((n + 1)); [ "$n" -ge 3 ]; }
poll 5 count && [ "$n" = 3 ] || fail "poll stopped at $n, not 3"
never() { false; }
poll 0 never && fail "poll passed a check that never passes"

# context_sources: the committed file, then PR_REVIEW_CONTEXT; comments, blanks, CRLF and repeats dropped.
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
mkdir "$repo/.claude"
printf '# decisions\r\nacme/adr\r\n\r\n  acme/platform@v2:docs/adr  # pinned\r\nnot-a-repo\r\n' >"$repo/.claude/review-context"
got=$(cd "$repo" && PR_REVIEW_CONTEXT='acme/adr, other/rules' context_sources | tr '\n' ' ')
want='acme/adr acme/platform@v2:docs/adr other/rules '
[ "$got" = "$want" ] || fail "context_sources gave '$got', not '$want'"
got=$(cd "$repo" && rm .claude/review-context && PR_REVIEW_CONTEXT='' context_sources)
[ -z "$got" ] || fail "context_sources without sources gave '$got'"

# fetch_context: a local repository stands in for GitHub once cloned; refresh and path handling.
src=$(mktemp -d)
git -C "$src" init -q && git -C "$src" config core.autocrlf false
mkdir "$src/docs"
echo one >"$src/docs/0001.md"
git -C "$src" add . && git -C "$src" -c user.name=t -c user.email=t@t commit -qm one
state="$repo/state"
dir="$state/context/acme_adr"
mkdir -p "$state/context" && git clone -q "$src" "$dir"
echo two >"$src/docs/0001.md"
git -C "$src" -c user.name=t -c user.email=t@t commit -qam two
got=$(fetch_context acme/adr:docs "$state") || fail "fetch_context failed to refresh"
[ "$got" = "$dir/docs" ] || fail "fetch_context gave '$got', not '$dir/docs'"
[ "$(cat "$dir/docs/0001.md")" = two ] || fail "fetch_context did not refresh the copy"
fetch_context acme/adr:missing "$state" >/dev/null && fail "fetch_context passed a missing path"
rm -rf "$src"

[ "$fails" = 0 ] && echo "helpers: all checks passed" || { echo "helpers: $fails failed"; exit 1; }
