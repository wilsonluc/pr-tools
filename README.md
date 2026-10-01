# PR Reviewer

A Claude Code plugin that reviews your pull requests from inside your Claude Code session.

When Claude pushes a branch that has an open pull request (or opens one with `gh pr create`), the plugin:

1. marks the new head commit with a `pr-reviewer` commit status: **pending**, shown in the PR merge box;
2. asks the session to run the `review-pr` skill, which starts a **read-only reviewer agent in the background**;
3. posts the reviewer's report as one PR comment (`### PR Reviewer at <sha>`), and sets the status to **success**
   with a link to the comment (or **error** if the review failed);
4. reviews again if new commits landed while it was reviewing.

It also blocks git commands that bypass the pull request flow: pushing or committing to the default branch,
force-pushing, `--no-verify` / `git commit -n`, and changing `core.hooksPath`.

## What it uses

- **Your Claude Code session and its login.** Reviews run as a subagent of the session you are working in, so they
  use your claude.ai subscription (or whatever your Claude Code is signed in with). No API key, no headless runs.
- **`gh`**, logged in to GitHub, to read the pull request and post the comment. Setting the commit status needs
  write access to the repository; without it the review still runs and posts.
- **`git` and a POSIX `sh`** (on Windows, the one that comes with Git for Windows). `jq` or `node` are used to read
  hook input when present; neither is required.

## Install

For yourself:

```
/plugin marketplace add wilsonluc/pr-reviewer
/plugin install pr-reviewer@pr-reviewer
```

For everyone working in a repository, commit this to its `.claude/settings.json`; teammates are offered the plugin
when they trust the folder:

```json
{
  "extraKnownMarketplaces": {
    "pr-reviewer": { "source": { "source": "github", "repo": "wilsonluc/pr-reviewer" } }
  },
  "enabledPlugins": { "pr-reviewer@pr-reviewer": true },
  "permissions": { "allow": ["Edit(./.pr-reviewer/**)"] }
}
```

The repository is private, so each person needs read access to it and `gh` (or git) logged in to GitHub.

## Use

- Automatic: push from Claude, as usual. The review arrives a few minutes later as a PR comment.
- By hand: `/pr-reviewer:review-pr 42` (or with no number for the current branch's pull request).
- Turn the automatic trigger off for a session: start Claude Code with `PR_REVIEWER_OFF=1`.

State (saved diffs, reports, the last reviewed head per pull request) lives in `.pr-reviewer/` at the repository
root. The plugin adds it to `.git/info/exclude`, so git ignores it without any change to the repository. Claude
writes each report there before posting it; to skip that permission prompt, allow it in your settings:

```json
{ "permissions": { "allow": ["Edit(./.pr-reviewer/**)"] } }
```

## The reviewer

`agents/reviewer.md` has only `Read`, `Grep` and `Glob`. It cannot run commands, change files or talk to GitHub. The
skill saves the pull request's diff to a file first, and posts the report itself. The reviewer looks for defects it
can tie to a concrete failure (logic, edge cases, error handling, races, security, broken contracts, misleading
tests) and skips style.

## Limits

- **Only pushes made through Claude trigger a review.** A `git push` from your own terminal does not go through
  Claude Code's hooks. Run `/pr-reviewer:review-pr` for those.
- **A review needs the session to stay open** until it posts. If the session closes first, the status stays
  pending until the next push or a manual run.
- **The guard only binds Claude.** People can still push to the default branch; use GitHub branch protection for
  that. Plugins can be disabled, so keep matching `permissions.deny` rules in the repository's
  `.claude/settings.json` if the guard matters.
- The guard matches command text, so a commit message that quotes a blocked command (for example `git push origin
  main`) is refused too. Reword the message.

## Development

```
sh plugins/pr-reviewer/tests/guard.test.sh      # guard checks in a throwaway repo
claude plugin validate --strict .               # marketplace
claude plugin validate --strict plugins/pr-reviewer
claude --plugin-dir plugins/pr-reviewer         # try it without installing
```
