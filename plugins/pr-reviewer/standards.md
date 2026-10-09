# Standards

The rules pr-reviewer checks every pull request against, in every repository. A repository's own written decisions (`STANDARDS.md`, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, decision records, review context) add rules, and win where they conflict with these.

## DRY: one source of truth

Every piece of knowledge has one authoritative home: a constant, a schema, a field name, a formula. Changing it is a one-place edit.

- DRY is about knowledge, not text. Two blocks that look alike but would change for different reasons stay separate.
- Extract on the third copy. Two copies are a note to watch. Three copies are a refactor.
- Before writing a helper, constant, or type, search for an existing one and reuse it.
- Knowledge shared across languages or services has one defining side or one shared schema. The other side derives from it or is checked against it by a test.
- Docs point to the source of truth (code, config, `--help`) instead of restating it.

## YAGNI: build what was asked for

The scope of a change is what its issue, spec, or description asks for. Code serves that scope and nothing else.

- Build for today's caller. Add configuration, parameters, and extension points when a second real use appears.
- An abstraction needs two concrete implementations. One implementation is a plain function or class.
- When a future need is likely, write it down in an issue. Leave the code at what is needed now.
- Never cut these for YAGNI: validation at trust boundaries, error handling that prevents data loss, and tests that prove the change works.

## Fail loud

Errors surface. Nothing fails silently.

- Every caught error is handled, rethrown, or logged with context. An empty `catch {}` or `except: pass` is a defect.
- An error names what failed and the input that caused it.
- Fall back to a default only when the requirements say the value may legitimately be missing.
- Retries are explicit, bounded, and logged.
- Every call that can wait has a timeout: network requests, database queries, subprocesses, and locks.

## Validate at the boundary

Data from outside the process is checked once, where it enters, and converted to typed values there.

- Outside data means requests, files, environment variables, command-line arguments, queues, and responses from other services.
- Code past the boundary trusts those types and does not check again.
- A validation failure is rejected with a clear error. It is never passed along half-checked.
- Work driven by outside data is bounded: input sizes, collection lengths, page sizes, loop counts, and recursion depth have a limit, and queries are paginated or capped.

## Release resources, watch background work

- Files, connections, sockets, and timers are released on every path, errors included: `using`, `with`, `defer`, or `try`/`finally`.
- Background work is awaited or has an error handler. A task or promise nobody awaits, or an `async void` method, loses its errors.

## No secrets in code, logs, or commits

- Credentials, tokens, and keys come from the environment or a secret store, never from source files or committed config.
- Logs and error messages never contain credentials, tokens, or personal data.
- Logs record chosen fields, never whole request, header, config, environment, user, or error objects that can carry secrets.
- A secret that reaches a commit is rotated, not just deleted.

## Security

- Database queries use parameters. Input is never concatenated into SQL.
- Processes are started with argument lists. Input is never interpolated into a shell string.
- Output to HTML, URLs, and other interpreted formats is escaped for that format.
- Code, tokens, and services get the least access they need.
- Every endpoint and action checks on the server that the caller may act on that specific resource, not only that the caller is logged in.
- Error responses to callers carry no internals: no stack traces, queries, or file paths. Those go to the logs.

## Versioned contracts

Public APIs, schemas, file formats, and message formats change compatibly, or they change version.

- Adding optional fields is compatible. Removing, renaming, or retyping a field is breaking.
- A breaking change bumps the version and says so in the PR title and description.

## Tests

- Every bug fix comes with a test that fails without the fix.
- Tests are deterministic: no sleeps, no real network or clock, and seeded randomness.
- Tests check behavior through public interfaces, not internal details.

## No magic values

Thresholds, timeouts, limits, and tuning values are named constants or config entries, defined once.

## Dependencies

- A new dependency comes with a reason in the PR: why the standard library or an existing dependency is not enough.
- Dependency versions are pinned through a lockfile or exact versions.

## Comments and dead code

- Comments explain why: a constraint, a trade-off, a workaround. The code shows what.
- Delete dead code, unused parameters, and commented-out blocks. Git keeps history.
- A change that makes existing docs wrong (README, docs, changelog, comments) updates them in the same pull request.

## Measure before optimizing

A change made for performance comes with numbers.

- Benchmark before and after on the same machine and inputs, and put both numbers in the PR.
- Optimize the bottleneck the measurement shows.
- When the gain is not measurable, keep the simpler version.
