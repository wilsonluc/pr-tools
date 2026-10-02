# PR Tools

Two Claude Code plugins for pull requests, working inside your Claude Code session:

- **pr-reviewer**: reviews each push to a pull request with read-only agents, two against the project's written
  decisions and guidelines (including decision records kept in other GitHub repositories) and two for bugs,
  confirms each finding with a validator agent, and posts a PR comment, inline comments and a `pr-reviewer` commit
  status.
- **pr-fixer**: fixes review findings (from pr-reviewer, another bot or a person). It checks each finding against
  the code, fixes each confirmed one everywhere it occurs, runs the project's checks and pushes.

Together they loop: push → review → fix → push → review, until a review is clean.

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

When Claude pushes a branch that has an open pull request (or opens one with `gh pr create`), it skips drafts and
pull requests opened by bots, and otherwise marks the new head with a **pending** `pr-reviewer` commit status and
asks the session to run `review-pr` with `--comment`. The skill, with every agent read-only and in the background:

1. stops if the pull request is closed, a draft, or this head was already reviewed; a **triage** agent (Haiku) stops
   it too for automated or trivial, plainly correct changes, and a **summary** agent (Sonnet) describes the change;
2. runs four reviewers at once, each given the title, description and summary:
   - two **decisions** reviewers (Sonnet), working independently: they weigh the change heavily against the
     project's written decisions (the review context below, `CONTRIBUTING.md`, decision folders such as
     `docs/adr/`, and the `CLAUDE.md` and `AGENTS.md` files at the root and above each changed file, each governing
     only its own folder), and report a breach only with the decision quoted and linked;
   - a **diff bugs** reviewer (Opus): significant bugs visible from the diff alone;
   - a **code bugs** reviewer (Opus): wrong logic and security holes in the code the change introduces;
3. checks each finding with its own **validator** (Opus for bugs, Sonnet for decisions) and drops any it cannot
   confirm;
4. posts the report as one PR comment (`### PR Reviewer at <sha>`), each finding linked to its lines at that
   commit, plus one inline comment per finding (with a GitHub suggestion when a small fix settles it), and sets the
   status to **success** with a link to it (or **error** if the review failed);
5. reviews again if new commits landed meanwhile, and hands the findings to pr-fixer when it is installed.

Reviewers report only what is certain and matters: code that will not build or load, logic wrong whatever the
input, and clear breaches of a written decision. Never: style, problems that need a particular input to show up,
problems the code already had, what linters catch, general quality no decision asks for, and rules the code sets
aside on purpose.

- By hand: `/pr-reviewer:review-pr 42` prints the review in the session and posts nothing; add `--comment` to post
  it (no number: the current branch's pull request).
- Off for a session: start Claude Code with `PR_REVIEWER_OFF=1`.
- The reviewer agent (`agents/reviewer.md`) has only `Read`, `Grep` and `Glob`: it cannot run commands, change
  files or talk to GitHub. The skill saves the diff and description, finds the guideline files and fetches the
  review context first, and posts the report itself. If GitHub refuses the inline comments (a line outside the
  diff), the report comment still holds every finding.
- Later reviews cover only what is new: the commits since the last reviewed head, with the previous posted report,
  kept locally in `.pr-reviewer/`, to check each finding was fixed in every place. A rebase, force push or merge, or
  a missing previous report, gets a full review. Findings are never taken from PR comments, which anyone can write.
- State (saved diffs, reports, the last reviewed head, fetched review context) lives in `.pr-reviewer/` at the
  repository root, added to `.git/info/exclude` so git ignores it. Claude writes each report there before posting;
  the `Edit(./.pr-reviewer/**)` allow rule above skips that permission prompt.

### Review context

Decision records kept in other GitHub repositories are listed in the repository's `.claude/review-context`, one per
line, as `owner/repo`, `owner/repo@ref` (a branch or tag) or `owner/repo[@ref]:path` (a folder or file inside it).
`#` starts a comment:

```
# Architecture decisions every change here must follow
acme/architecture:decisions
acme/platform@v2:docs/adr
```

`PR_REVIEW_CONTEXT` adds more for a session (separated by spaces or commas). Before each review, `prepare.sh`
clones each repository with `gh` (shallow, into `.pr-reviewer/context/`) or brings its copy up to date, so `gh`
needs read access to them. A source it cannot fetch is reported in a note and the review goes on without it.

## pr-fixer

`/pr-fixer:fix-pr 42` (or the hand-off from pr-reviewer):

1. checks the checkout is the pull request's branch, clean and at its head (it never switches branches, stashes or
   pulls on its own);
2. takes the latest review, checks each finding against the code, and decides **fix**, **skip** (with the reason)
   or **ask** (a decision only you can make: design, agreed behaviour);
3. fixes each confirmed finding everywhere the same mistake occurs, adds a test where the project has tests for
   that code, runs the project's checks, commits `fix: address review of #42` and pushes, which starts the next
   review.

There is no round cap. To set one, start Claude Code with `PR_FIXER_MAX_ROUNDS=<n>`: a round is one
`fix: address review of #N` commit, and any other commit at the tip of the branch starts the count again.

## Limits

- **Only pushes made through Claude start a review.** A `git push` from your own terminal does not go through
  Claude Code's hooks; run `/pr-reviewer:review-pr` for those.
- **The session has to stay open** until a review posts. If it closes first, the status stays pending until the
  next push or a manual run.
- **Nothing here stops a push to the default branch.** Use GitHub branch protection for that.
- **The review context is read at the version fetched.** Decisions changed after the fetch apply from the next
  review.

## Development

```
sh plugins/pr-reviewer/tests/helpers.test.sh   # trigger pattern, poll, review context (no GitHub needed)
claude plugin validate --strict .              # marketplace
claude plugin validate --strict plugins/pr-reviewer
claude plugin validate --strict plugins/pr-fixer
claude --plugin-dir plugins/pr-reviewer --plugin-dir plugins/pr-fixer   # try them without installing
```
