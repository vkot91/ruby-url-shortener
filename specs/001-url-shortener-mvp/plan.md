# Implementation Plan: URL Shortener MVP

**Branch**: `001-url-shortener-mvp` | **Date**: 2026-08-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-url-shortener-mvp/spec.md`

## Summary

Build a link shortener whose read path is deliberately separated from its write path. Two
deployables share one Postgres and one Redis: a Rails application serving the public short domain
and the JSON API, and a Next.js application serving the creator dashboard and the admin area.

The redirect is handled by Rack middleware that runs before the Rails router, resolves the code
from Redis, and returns a 302 without instantiating a controller, a session, or an ORM object.
Clicks are pushed onto a Redis list and drained into Postgres in batches by a background worker.

The build order is intentionally non-obvious: the naive database-only redirect ships first and is
load-tested to failure, and that number is committed before any cache exists. The cached version is
then measured with the identical harness. Both implementations remain runnable behind a flag.

## Technical Context

**Language/Version**: Ruby 3.4 (backend), TypeScript 5.7 on Node 24 LTS (frontend)

**Primary Dependencies**

*Backend*: Rails 8.0 (API-only + Rack middleware, `has_secure_password` and `rate_limit`), the
`jwt` gem for HS256 access tokens, Puma, `redis-rb` 5.x with connection pooling, Sidekiq 7 for
background work. No cookie middleware is in the stack at all (research.md D10).

*Frontend*: Next.js 15 (App Router) with React 19, Tailwind CSS 4, shadcn/ui for accessible
primitives (dialog, table, toast, form), zod for schema validation shared between forms and the
typed API client, react-hook-form with `@hookform/resolvers` for form state, and TanStack Query
scoped **only** to polling the dashboard click counts.

*Deliberately excluded*: no client state manager (Zustand, Redux) — the access token lives in
memory, the refresh token in an httpOnly cookie held by the Next.js BFF, and everything else is
server data; no charting library — MVP renders one integer per link,
and charts belong to the out-of-scope paid analytics tier.

**Storage**: PostgreSQL 17 as system of record; Redis 7.4 as read cache, click buffer, and Sidekiq
broker (logically separated by database index)

**Testing**: RSpec + FactoryBot for the backend, Vitest + Testing Library for the frontend,
Playwright for one end-to-end path, k6 for the load test

**Quality gates**: RuboCop and ESLint + Prettier, configured in Phase 1 and blocking in CI from the
first pull request

**Target Platform**: Linux containers; single-host Docker Compose for the reference benchmark

**Project Type**: Web application — separate backend and frontend

**Performance Goals**: ≥5 000 sustained redirects/second on reference hardware; ≥95% of redirects
served without a Postgres read; ≥99.9% redirect availability under load

**Constraints**: ≤50 ms service-added latency at p99 under target load; zero synchronous work on the
redirect path beyond one Redis GET; no plain visitor IP persisted; no cookie set on any path, since
the cookie middleware is absent from the stack entirely

**Scale/Scope**: MVP targets ~10 000 accounts and ~500 000 links, with click volume assumed three
orders of magnitude above link volume. Four user stories, 35 functional requirements.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Gate | Pre-Phase-0 | Post-Phase-1 |
|---|---|---|---|
| I. The Redirect Path Is Sacred | Redirect does no synchronous work beyond resolving the destination; never rate-limited by plan | PASS | **PASS from 3C; WAIVED for 3A/3B** — see waiver below. From T050 onward: Rack middleware, one Redis GET, one `LPUSH`; no controller, session, or ActiveRecord object instantiated |
| II. Measure Before, Measure After | Naive baseline exists, is runnable, and is measured before optimisation | PASS | PASS — `REDIRECT_CACHE_ENABLED` flag keeps both paths live; identical k6 script for both runs; results committed as data |
| III. The Store Enforces Its Own Invariants | Uniqueness by constraint, not check-then-write | PASS | PASS — unique index on `links.code`, insert-and-rescue `PG::UniqueViolation`, no existence query |
| IV. Cache Invalidation Belongs To The Write | Invalidation in the same operation as the write, before acknowledgement | PASS | PASS — `after_commit` on `Link` deletes the cache key before the HTTP response returns; see research.md for why after-commit rather than in-transaction |
| V. The Visitor Is Not The Product | No plain IP stored, no redirect cookie, audited admin access to customer analytics | PASS | PASS — MVP click record holds only `link_id` and timestamp; no IP reaches the click row at all. Bearer-token auth means `ActionDispatch::Cookies` is not in the middleware stack, so "no cookie on the redirect" is structural rather than asserted |

**Result**: All gates pass for the delivered system. One time-boxed waiver is recorded below.

### Recorded waiver — Principle I, sub-phases 3A and 3B

The naive implementation (tasks T035, T036) queries Postgres on every redirect and inserts a click
row synchronously. Both are Principle I violations, and both are the point: Principle II requires a
measured baseline, and a baseline that already avoids the bottleneck measures nothing.

- **Scope**: tasks T035–T044 only.
- **Expiry**: task T045. Principle I is unconditional from T045 onward and is enforced by T052,
  which asserts zero Postgres queries and no `Set-Cookie` on a cache hit.
- **Required disclosure**: PR 3 and PR 4 bodies MUST restate this waiver, per the Governance
  section's rule that an intentional violation carries its reasoning and an explicit expiry
  condition. An undocumented violation is a defect; a documented, expiring one is a measurement.

## Project Structure

### Documentation (this feature)

```text
specs/001-url-shortener-mvp/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── design.md            # Phase 1 output — visual specification for the nine MVP surfaces
├── contracts/           # Phase 1 output
│   ├── openapi.yaml
│   └── redirect.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Created by /speckit-tasks, not by this command
```

### Source Code (repository root)

```text
backend/
├── app/
│   ├── controllers/
│   │   ├── concerns/
│   │   ├── api/v1/          # links, sessions, registrations, token refresh, stats
│   │   └── api/v1/admin/    # links, accounts, reports, blocked_domains, health
│   ├── middleware/
│   │   └── redirect_middleware.rb   # the hot path; runs before the Rails router
│   ├── models/              # account, link, click, blocked_domain, report
│   ├── services/
│   │   ├── auth/            # access_token (JWT), refresh_tokens (rotation + reuse detection)
│   │   ├── links/           # creator, updater, destroyer, code_generator
│   │   ├── urls/            # normalizer, safety_validator (SSRF + blocklist)
│   │   └── cache/           # link_cache, negative_cache
│   ├── jobs/
│   │   └── clicks/          # flush_job (drains the Redis buffer in batches)
│   └── views/
│       └── pages/           # not_found, banned, error — HTML on the short domain
├── config/
├── db/
│   └── migrate/
├── lib/
└── spec/
    ├── models/
    ├── requests/
    ├── services/
    ├── middleware/
    └── integration/

frontend/
├── src/
│   ├── app/
│   │   ├── (auth)/          # sign-in, sign-up
│   │   ├── (dashboard)/     # link list, link create, link detail
│   │   └── admin/           # moderation queue, link search, accounts, health
│   ├── components/
│   ├── lib/                 # api client, BFF route handlers holding the refresh token
│   └── types/
└── tests/

load/
├── redirect.js              # the k6 script — identical across both runs
├── seed.rb                  # generates the fixed link corpus
└── results/                 # committed measurements: naive.json, cached.json

backend/docker-compose.yml   # postgres and redis only — the apps run natively
```

**Structure Decision**: Web application with separate `backend/` and `frontend/` trees. The split is
not stylistic — the two have different traffic profiles. `backend/` absorbs all public redirect
traffic on the short domain and must stay deployable and scalable on its own; `frontend/` serves
authenticated humans on the app domain at a tiny fraction of the request volume. `load/` is a
top-level peer rather than a subdirectory of either, because per Principle II its output is a
project deliverable and not test scaffolding.

## Implementation Phases

Phases are sequential and use the same numbering as `tasks.md`. Each produces one pull request
scoped to demonstrable work; `tasks.md` carries the task-level breakdown and the PR table.

### Phase 1+2 — Setup and Foundation (tasks.md Phases 1 and 2)

Docker Compose (Postgres and Redis; the apps run natively), Rails and Next.js skeletons, RuboCop
and ESLint configured, and CI running both test suites plus both linters as blocking checks. No
feature behaviour.

Linting is established here rather than at polish time on purpose: a style config introduced after
the code exists produces a large mechanical diff that buries real review, and every intervening pull
request is reviewed against a standard that is not yet enforced. Configured first and enforced by
CI from PR 1, style debt never accumulates.

**Exit**: `cd backend && docker compose up -d` plus `bin/rails s` and `pnpm dev` give a running
stack, green suites, and clean blocking linters.

### Phase 3A — Naive redirect (US1, partial)

Accounts, registration, sign-in. Link creation with random 7-character codes, URL normalisation,
SSRF and blocklist validation, unique-index-with-retry allocation. Redirect resolved by a direct
Postgres query on every request. Clicks written synchronously, one row per redirect. Not-found page.
**Exit**: a link can be created via API and redirects correctly. Deliberately slow.

### Phase 3B — Baseline measurement (SC-004, Principle II)

k6 script, fixed seed corpus, single-host reference environment. Run against Phase 3A until it
breaks. Commit `load/results/naive.json` and a short written analysis of *where* it broke —
connection pool exhaustion, per-request click insert, or query latency. **Exit**: a committed
number and a named bottleneck.

> This phase produces no product code. It is not optional and it is not merged with Phase 3C.
> Skipping it forfeits the project's primary deliverable.

### Phase 3C — Read path optimisation (US1 complete)

Rack redirect middleware ahead of the Rails router. Redis cache with bounded memory, LRU eviction,
24h TTL refreshed on read. Negative caching of absent codes for 60s. Single-flight rebuild on miss.
Cache invalidation wired into `Link` writes. Clicks buffered in a Redis list and drained by a
Sidekiq worker in batches of 1 000. **Exit**: same k6 script, `load/results/cached.json` committed,
delta documented.

### Phase 4 — Statistics and dashboard (US2)

Click counter surfaced per link. Next.js sign-in, link list, link creation, copy-to-clipboard.
**Exit**: creator sees an accurate count within 30 seconds of a click.

### Phase 5 — Editing and deletion (US3)

Destination and name editing with immediate cache invalidation, soft delete, ownership enforcement.
**Exit**: an automated test edits a link and the very next request follows the new destination.

### Phase 6 — Moderation (US4)

Admin role, link search by code or destination, ban link, ban account, blocked-domain list, safety
warning page with report control, report queue, health metrics endpoint. **Exit**: a reported link
can be found and banned, and the next visitor sees the warning page.

### Phase 7 — Polish

Click retention purge, quickstart validation, end-to-end test, security review, final load test
re-run, and the README that leads with the naive-versus-cached numbers. No lint cleanup — that is
enforced from Phase 1 onward. **Exit**: every
Constitution Check gate above re-verified against the built system.

## Complexity Tracking

Not applicable — Constitution Check passes with no violations.
