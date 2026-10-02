# PR Tools

Two Claude Code plugins for pull requests, working inside your Claude Code session:

- **pr-reviewer**: reviews each push to a pull request with a read-only reviewer agent, and posts one PR comment
  and a `pr-reviewer` commit status.
- **pr-fixer**: fixes review findings (from pr-reviewer, another bot or a person). It checks each finding against
  the code, fixes the confirmed ones, runs the project's checks and pushes, and it blocks git commands that bypass
  the pull request flow.

Together they loop: push → review → fix → push → review, until a review is clean or 5 fix rounds in a row have run.

## What they use

- **Your Claude Code session and its login.** Reviews and fixes run in the session you are working in (the reviewer
  as a background subagent), so they use your claude.ai subscription, or whatever your Claude Code is signed in
  with. No API key, no headless runs.
- **`gh`**, logged in to GitHub, to read pull requests and post comments. Setting the commit status needs write
  access to the repository; without it the review still runs and posts.
- **`git` and a POSIX `sh`** (on Windows, the one that comes with Git for Windows). `jq` or `node` are used to read
  hook input when present; neither is required.

## Install

For yourself:

```
/plugin marketplace add wilsonluc/pr-tools
/plugin install pr-reviewer@pr-tools
/plugin install pr-fixer@pr-tools
```

For everyone working in a repository, commit this to its `.claude/settings.json`; teammates are offered the plugins
when they trust the folder:

```json
{
  "extraKnownMarketplaces": {
    "pr-tools": { "source": { "source": "github", "repo": "wilsonluc/pr-tools" } }
  },
  "enabledPlugins": { "pr-reviewer@pr-tools": true, "pr-fixer@pr-tools": true },
  "permissions": { "allow": ["Edit(./.pr-reviewer/**)"] }
}
```

The repository is private, so each person needs read access to it and `gh` (or git) logged in to GitHub.

## pr-reviewer

When Claude pushes a branch that has an open pull request (or opens one with `gh pr create`), it:

1. marks the new head with a `pr-reviewer` commit status: **pending**, shown in the PR merge box;
2. asks the session to run the `review-pr` skill, which starts the **read-only reviewer agent in the background**;
3. posts the report as one PR comment (`### PR Reviewer at <sha>`) and sets the status to **success** with a link
   to it (or **error** if the review failed);
4. reviews again if new commits landed meanwhile, and hands the findings to pr-fixer when it is installed.

- By hand: `/pr-reviewer:review-pr 42` (no number: the current branch's pull request).
- Off for a session: start Claude Code with `PR_REVIEWER_OFF=1`.
- The reviewer (`agents/reviewer.md`) has only `Read`, `Grep` and `Glob`: it cannot run commands, change files or
  talk to GitHub. The skill saves the diff first and posts the report itself. It reports defects it can tie to a
  concrete failure and skips style.
- Reviews go deep rather than fast: the reviewer works through each kind of input a change can get, looks for the
  same mistake elsewhere, and reports only once a full pass finds nothing new, so one review takes several minutes
  and the fix loop needs fewer rounds. pr-fixer, in turn, fixes each finding's whole class.
- Later reviews cover only what is new: the commits since the last reviewed head, with the previous posted report,
  kept locally in `.pr-reviewer/`, to check each finding was fixed in every similar case. A rebase, force push or
  merge, or a missing previous report, gets a full review. Findings are never taken from PR comments, which anyone
  can write.
- State (saved diffs, reports, the last reviewed head) lives in `.pr-reviewer/` at the repository root, added to
  `.git/info/exclude` so git ignores it. Claude writes each report there before posting; the
  `Edit(./.pr-reviewer/**)` allow rule above skips that permission prompt.

## pr-fixer

`/pr-fixer:fix-pr 42` (or the hand-off from pr-reviewer):

1. checks the checkout is the pull request's branch, clean and at its head (it never switches branches, stashes or
   pulls on its own);
2. takes the latest review, checks each finding against the code, and decides **fix**, **skip** (with the reason)
   or **ask** (a decision only you can make: design, agreed behaviour);
3. fixes the confirmed ones, runs the project's checks, commits `fix: address review of #42` and pushes, which
   starts the next review.

It stops after 5 rounds in a row (`PR_FIXER_MAX_ROUNDS`): a round is one `fix: address review of #N` commit, and any
other commit at the tip of the branch starts the count again.

Its guard hook refuses, for every command Claude runs: pushing or committing to the default branch, force-pushing,
`--no-verify` / `git commit -n`, and changing `core.hooksPath`.

## Limits

- **Only pushes made through Claude start a review.** A `git push` from your own terminal does not go through
  Claude Code's hooks; run `/pr-reviewer:review-pr` for those.
- **The session has to stay open** until a review posts. If it closes first, the status stays pending until the
  next push or a manual run.
- **The guard only binds Claude.** People can still push to the default branch; use GitHub branch protection for
  that. Plugins can be disabled, so keep matching `permissions.deny` rules in the repository's
  `.claude/settings.json` if the guard matters.
- The guard matches command text, so a commit message that quotes a blocked command (for example `git push origin
  main`) is refused too. Reword the message.

## Development

```
sh plugins/pr-fixer/tests/guard.test.sh        # guard checks in a throwaway repo
sh plugins/pr-reviewer/tests/trigger.test.sh   # after-push trigger pattern
claude plugin validate --strict .              # marketplace
claude plugin validate --strict plugins/pr-reviewer
claude plugin validate --strict plugins/pr-fixer
claude --plugin-dir plugins/pr-reviewer --plugin-dir plugins/pr-fixer   # try them without installing
```
