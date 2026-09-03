# Instructions for Claude

## Keep the Bruno collection current

`bruno/` is a Bruno collection covering the backend API. It is treated as part
of the codebase, not as a side artifact: **any change to the HTTP surface
updates the collection in the same change.**

That means all of these, not just the first:

- an endpoint added, removed, or moved to a different path or method;
- a request or response body whose shape changed;
- a new `error.code`, or an existing one that now arrives with a different
  status;
- a new authentication or rate-limiting rule that a client would have to know
  about;
- a guarantee that became load-bearing and had no assertion — a header, an
  ordering, an absence.

### What a request in the collection looks like

Each `.bru` file carries three things, and a request missing any of them is
incomplete:

1. The call itself, in the numbered folder matching its place in the run order.
2. A `tests` block asserting what the endpoint *guarantees*, not merely that it
   answered — the status, the fields a client branches on, and the headers that
   are requirements rather than side effects.
3. A `docs` block saying what the endpoint promises and why, referencing the
   FR or decision behind it, plus variations worth pasting in by hand.

### Rules that are easy to get wrong

- **Chain state through runtime variables** (`bru.setVar`), never environment
  variables. Bruno writes environment variables set from a script back into
  `environments/Local.bru`, which would commit a live credential and produce a
  diff on every run. `environments/Local.bru` holds only where the stack is:
  `baseUrl`, `shortDomain`, `appUrl`.
- **Declare auth once**, at the collection level. A request that must go out
  unauthenticated sets `auth: none` for itself, and that is the assertion.
- **Turn redirect following off** on anything under `03 - Redirect`. Bruno
  follows by default, which hides the status, `Location`, and `Cache-Control`
  those requests exist to check.
- **Keep the collection re-runnable end to end.** Anything that would collide
  with a unique index on a second run (an email address, say) is generated in a
  pre-request script.

### Before reporting the work done

Run it against the live stack and report the result next to the RSpec one:

```sh
cd backend && docker compose up -d && bin/rails s   # separate shell
cd bruno   && npx @usebruno/cli run --env Local
```

A collection that lags the code is worse than no collection, because it goes on
passing while silently covering nothing new.

## The CI gates run before every commit

`hooks/pre-commit` runs the two backend checks that block CI, over the whole of
`backend/`, and refuses the commit if either finds something:

| Check | CI job it mirrors |
|---|---|
| `bundle exec rubocop` | `backend-lint` |
| `bin/brakeman --no-pager` | `backend-security` |

Both run before the commit is refused, and both report. Stopping at the first
failure would hide the second until the first was fixed, which turns one round
trip into two.

They inspect the whole tree rather than only the staged files on purpose: an
offense that is already committed fails CI on the next push whoever wrote it, so
the gate has to see it too. Brakeman has no staged-file mode in any case — it
needs the whole application to trace data flow through it.

A fresh clone has to point Git at the directory once:

```sh
git config core.hooksPath hooks
```

Claude Code runs the same script as a `PreToolUse` hook on `git commit`
(`.claude/settings.json`), so a failure surfaces before the commit is even
attempted rather than as a rejected command.

### When Brakeman is wrong

It reports data flow it cannot follow, so a finding is sometimes a false
positive — an interpolation whose values are already quoted or cast, for
instance. Two things are true about that and both matter:

- The finding still blocks the commit. Silencing it is a decision, so it is
  recorded rather than argued: `bin/brakeman -I` writes the reviewed exception
  into `config/brakeman.ignore`, where it is reviewable in the diff.
- Reach for the ignore file second, not first. A scanner objecting to the shape
  of a query is often right about the shape even when it is wrong about the
  vulnerability — dynamic SQL that is safe today is safe only until someone
  edits it, and a statement built per call cannot be plan-cached. Rewriting to
  bound parameters usually removes the finding and improves the code.

`git commit --no-verify` bypasses the Git hook entirely; `SKIP_RUBOCOP=1` and
`SKIP_BRAKEMAN=1` skip one check each. All three only move the failure to CI, so
bypass to stage a work-in-progress commit, never to land one.
