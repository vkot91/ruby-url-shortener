---
description: "Task list for URL Shortener MVP"
---

# Tasks: URL Shortener MVP

**Input**: Design documents from `/specs/001-url-shortener-mvp/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [design.md](./design.md)

**Tests**: Test tasks ARE included. Not by default — the project constitution's Development Workflow section requires that non-trivial logic arrive with at least one automated test that fails if the logic breaks. Test volume is not the goal; each test task below names the specific behaviour it protects.

**Organization**: Tasks are grouped by user story. Phase 3 (US1) is additionally split into three sub-phases because Principle II requires the naive baseline to be built and measured *before* the optimised path exists.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

## Task IDs

IDs are stable identifiers, not execution order. Execution order is the order tasks appear in this
file. Tasks added after the initial generation take the next free number (T104+) and are placed in
the phase where they belong, so existing IDs stay valid in commit messages and PR bodies.

## Path Conventions

Web application: `backend/` (Rails 8, Ruby 3.4), `frontend/` (Next.js 15), `load/` (k6 harness — a deliverable, not scaffolding).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: A running stack and green empty suites. No feature behaviour.

- [X] T001 Create `.tool-versions` pinning `ruby 3.4.8` and `nodejs 24.19.0` at repository root
- [X] T002 Generate API-only Rails 8 app in `backend/` with `--api --database=postgresql --skip-solid`
- [X] T003 [P] Generate Next.js 15 app in `frontend/` with App Router, TypeScript, Tailwind 4
- [X] T004 Write `docker-compose.yml` at repository root with postgres:17, redis:7.4, backend, frontend, sidekiq services
- [X] T005 [P] Configure RSpec, FactoryBot, and DatabaseCleaner in `backend/spec/rails_helper.rb`
- [X] T006 [P] Configure Vitest and Playwright in `frontend/vitest.config.ts` and `frontend/playwright.config.ts`
- [X] T099 [P] RuboCop configuration in `backend/.rubocop.yml` and ESLint + Prettier configuration in `frontend/eslint.config.mjs` — established before any feature code exists, so no retrofit diff is ever needed
- [X] T007 [P] Add CI workflow in `.github/workflows/ci.yml` running both test suites **and both linters as blocking checks** (depends on T099 — a lint config CI does not enforce is decoration)
- [X] T008 [P] Write `.gitignore` covering Rails, Node, and `.claude/` per the Spec Kit security note
- [X] T009 Set `maxmemory` and `maxmemory-policy allkeys-lru` in `docker-compose.yml` redis service, and put Sidekiq on a separate Redis database index (Principle IV, research.md D9)
- [X] T010 [P] Add `backend/config/initializers/redis.rb` with a connection pool sized for Puma thread count
- [X] T104 [P] Install and configure the frontend libraries from research.md D15 — `pnpm dlx shadcn@latest init`, plus `zod`, `react-hook-form`, `@hookform/resolvers`, `@tanstack/react-query` — in `frontend/package.json` and `frontend/components.json`

**Checkpoint**: `docker compose up` yields a running stack; `bundle exec rspec` and `pnpm test` pass with zero tests; `rubocop` and `eslint` pass clean and are blocking in CI.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema and cross-cutting infrastructure every story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T011 [P] Migration for `accounts` table per data-model.md in `backend/db/migrate/` (citext email unique, role check, plan check, banned_at)
- [X] T012 [P] Migration for `sessions` table in `backend/db/migrate/` (token_digest unique, FK cascade)
- [X] T013 Migration for `links` table in `backend/db/migrate/` — unique index on `code`, partial index `(account_id, created_at DESC) WHERE deleted_at IS NULL`, gin_trgm index on `destination_url`
- [X] T014 [P] Migration for `clicks` table in `backend/db/migrate/` — deliberately no IP column (FR-024, Principle V)
- [X] T015 [P] Migration for `blocked_domains` table in `backend/db/migrate/`
- [X] T016 [P] Migration for `reports` table in `backend/db/migrate/` with `(status, created_at)` index
- [X] T017 [P] `Account` model with `has_secure_password` and role predicates in `backend/app/models/account.rb`
- [X] T018 `RefreshToken` model, `Auth::AccessToken` (HS256 encode/decode with the algorithm pinned), and `Auth::RefreshTokens` (issue, rotate, revoke family) in `backend/app/models/refresh_token.rb` and `backend/app/services/auth/` (research.md D10)
- [X] T114 Bearer-token `Authentication` controller concern in `backend/app/controllers/concerns/authentication.rb` — decodes the claims, loads `current_account` lazily, and distinguishes `token_expired` from `unauthenticated`
- [X] T115 Auth service specs in `backend/spec/services/auth/` covering the `alg: none` and wrong-secret attacks, expiry, rotation, and **reuse detection revoking the family**; plus request specs in `backend/spec/requests/foundation_spec.rb` asserting an authenticated request issues zero queries and that Rails sets no cookie on any path (D10, FR-015)
- [X] T019 [P] `Link` model with associations and scopes (`active`, `owned_by`) in `backend/app/models/link.rb`
- [X] T020 [P] JSON error envelope and rescue_from handlers in `backend/app/controllers/concerns/error_handling.rb` matching the `Error` schema in contracts/openapi.yaml
- [X] T021 [P] Structured single-line request logging in `backend/config/initializers/logging.rb` (the redirect path is capped at one line — contracts/redirect.md)
- [X] T022 Define `/api/v1` namespace and reserved top-level paths in `backend/config/routes.rb` (FR-012)

- [X] T123 Generate the design canvas with Claude Design from the brief in design.md §10 — eleven artboards covering the nine surfaces, with the link list and the moderation queue in both themes — and record the published canvas URL in design.md §10 so the written spec and the visual reference point at each other. Blocks T121 and T122: a component built before its screen has been drawn gets its API guessed rather than derived
- [ ] T120 [P] Apply the design tokens from design.md §3 — replace the `:root` and `.dark` blocks in `frontend/src/app/globals.css`, set `--radius` to `0.75rem`, add `--input-border` and `--success`, and bind Figtree and JetBrains Mono via `next/font/google` in `frontend/src/app/layout.tsx` (design.md §3, §4, §5.2)
- [ ] T121 Install the shadcn components listed in design.md §7 and build the dashboard app shell in `frontend/src/app/(dashboard)/layout.tsx`, including `<ThemeToggle>` with a pre-hydration script so dark theme does not flash light (design.md §6.1; FR-003 — creators get no admin affordance rendered at all)

**Checkpoint**: Schema migrates cleanly; models load; the app shell renders in both themes; user story work can begin.

---

## Phase 3: User Story 1 - Shorten a link and share it (Priority: P1) 🎯 MVP

**Goal**: A registered creator turns a long URL into a short one, and anyone opening it reaches the destination.

**Independent Test**: Register, create one link, open the short URL in a fresh client, land on the destination. Delivers the core value with no other story implemented.

> **Sub-phase ordering is mandatory.** 3A ships a deliberately slow implementation. 3B measures it and commits the number. Only then does 3C make it fast. Collapsing 3B into 3C forfeits the project's primary deliverable (Principle II, plan.md Phase 3B).

### 3A — Naive implementation (no cache)

- [ ] T023 [P] [US1] Request spec for registration and sign-in in `backend/spec/requests/api/v1/auth_spec.rb` — asserts the token pair shape and that no `Set-Cookie` is emitted
- [ ] T024 [P] [US1] Unit spec for URL normalisation edge cases in `backend/spec/services/urls/normalizer_spec.rb`
- [ ] T025 [P] [US1] Unit spec for SSRF rejection (private, loopback, link-local, self-referential, non-http scheme) in `backend/spec/services/urls/safety_validator_spec.rb`
- [ ] T026 [P] [US1] Unit spec asserting code allocation retries on `RecordNotUnique` and never issues an existence query in `backend/spec/services/links/code_generator_spec.rb`
- [ ] T027 [US1] `Api::V1::RegistrationsController` and `Api::V1::SessionsController` in `backend/app/controllers/api/v1/` returning a `TokenPair` per contracts/openapi.yaml (FR-001)
- [ ] T116 [US1] `Api::V1::Auth::RefreshController#create` in `backend/app/controllers/api/v1/auth/refresh_controller.rb` — rotates the pair, returns `invalid_refresh_token` or `token_reuse_detected` on 401 (contracts/openapi.yaml `/auth/refresh`)
- [ ] T117 [P] [US1] Request spec for the full token lifecycle in `backend/spec/requests/api/v1/token_lifecycle_spec.rb`: sign in, refresh, confirm the old token is dead, replay it, confirm the family is gone and the client must sign in again
- [ ] T112 [US1] `rate_limit` on `Api::V1::RegistrationsController#create`, `Api::V1::SessionsController#create`, and the refresh endpoint — per hashed IP on all three, plus per hashed email on sign-in (FR-036)
- [ ] T113 [P] [US1] Request spec asserting the auth limiters return 429 and that the refusal body is indistinguishable for a registered and an unregistered address, in `backend/spec/requests/api/v1/auth_rate_limit_spec.rb` (FR-036)
- [ ] T028 [P] [US1] `Urls::Normalizer` in `backend/app/services/urls/normalizer.rb` (FR-008)
- [ ] T029 [P] [US1] `Urls::SafetyValidator` in `backend/app/services/urls/safety_validator.rb` — resolves DNS before accepting, re-usable on edit (FR-006, research.md D11)
- [ ] T030 [P] [US1] `Links::CodeGenerator` in `backend/app/services/links/code_generator.rb` — 7 chars base62 via SecureRandom (FR-009)
- [ ] T031 [US1] `Links::Creator` in `backend/app/services/links/creator.rb` — insert-and-rescue allocation, no check-then-write (FR-010, Principle III)
- [ ] T032 [US1] `Api::V1::LinksController#create` with `rate_limit` and the 50-link free cap in `backend/app/controllers/api/v1/links_controller.rb` (FR-004, FR-005)
- [ ] T033 [US1] Request spec covering all six `error.code` rejection reasons in `backend/spec/requests/api/v1/links_create_spec.rb`
- [ ] T034 [US1] Add `REDIRECT_CACHE_ENABLED` flag to `backend/config/application.rb`, defaulting to false (Principle II — both paths stay runnable)
- [ ] T035 [US1] Naive `RedirectsController#show` querying Postgres on every request in `backend/app/controllers/redirects_controller.rb` (FR-013 — satisfies the redirect itself; FR-014 deliberately unmet until T050)
- [ ] T036 [US1] Synchronous per-click `INSERT` in the naive path, isolated so 3C can replace it in one place
- [ ] T037 [P] [US1] Not-found page view in `backend/app/views/pages/not_found.html.erb` (FR-017) — layout and the inlined CSS subset per design.md §6.9 and §8
- [ ] T038 [US1] Redirect request spec asserting 302, `Location`, `Cache-Control: no-store`, and **absence of `Set-Cookie`** in `backend/spec/requests/redirect_spec.rb` (FR-015, FR-016)
- [ ] T039 [US1] Spec asserting two accounts shortening an identical destination get two distinct codes and independent counters in `backend/spec/requests/api/v1/links_dedup_spec.rb` (FR-011)
- [ ] T105 [US1] Spec asserting redirects are never throttled: an account far over its link cap and past its hourly creation limit still redirects, and no rate limiter applies to `GET /:code`, in `backend/spec/requests/redirect_never_throttled_spec.rb` (FR-019, Principle I)

**Checkpoint 3A**: Links can be created and redirect correctly. Deliberately slow.

### 3B — Baseline measurement (produces no product code)

- [ ] T040 [P] [US1] Deterministic 10 000-link corpus generator in `load/seed.rb`
- [ ] T041 [US1] k6 script with Zipf-distributed code selection in `load/redirect.js` — this exact file is reused unchanged in 3C (research.md D13)
- [ ] T042 [P] [US1] Document the reference environment (host spec, compose profile, k6 flags) in `load/README.md`
- [ ] T043 [US1] Run k6 against the naive build and commit results to `load/results/naive.json`
- [ ] T044 [US1] Write baseline analysis in `load/results/naive-analysis.md` naming the actual bottleneck — connection pool exhaustion, per-click insert, or query latency

**Checkpoint 3B**: A committed number and a named bottleneck. **Do not proceed without these files committed.**

### 3C — Read path optimisation

- [ ] T045 [P] [US1] Spec for `GETEX` TTL refresh-on-read behaviour in `backend/spec/services/cache/link_cache_spec.rb` (research.md D6)
- [ ] T046 [P] [US1] Spec for the `__404__` sentinel and its 60s TTL in `backend/spec/services/cache/negative_cache_spec.rb` (FR-017, D7)
- [ ] T047 [P] [US1] `Cache::LinkCache` in `backend/app/services/cache/link_cache.rb` — packed value carrying destination plus banned/deleted/account-banned flags
- [ ] T048 [P] [US1] `Cache::NegativeCache` in `backend/app/services/cache/negative_cache.rb`
- [ ] T049 [US1] Single-flight rebuild lock (`SET NX EX 5`) in `backend/app/services/cache/single_flight.rb` (D5, SC-007)
- [ ] T050 [US1] `RedirectMiddleware` in `backend/app/middleware/redirect_middleware.rb` — one `GETEX`, no controller, no session, no ActiveRecord object (FR-013, FR-014, Principle I, D1)
- [ ] T051 [US1] Insert middleware before `ActionDispatch::Session` in `backend/config/application.rb`
- [ ] T052 [US1] Middleware spec asserting zero Postgres queries on a cache hit and no `Set-Cookie` in `backend/spec/middleware/redirect_middleware_spec.rb` (Principle I gate conditions, contracts/redirect.md)
- [ ] T053 [US1] Replace the synchronous insert with `LPUSH clicks:buffer` constructed after the response triple, in `backend/app/middleware/redirect_middleware.rb` (FR-021)
- [ ] T054 [US1] Spec asserting a Redis failure during click recording does not alter the redirect response, and that a lost in-flight batch costs only statistics, in `backend/spec/middleware/redirect_resilience_spec.rb` (FR-022, SC-008)
- [ ] T055 [US1] `Clicks::FlushJob` in `backend/app/jobs/clicks/flush_job.rb` — atomic `LPOP key 1000`, bulk insert, grouped counter `UPDATE` (FR-020, D4)
- [ ] T056 [US1] Sidekiq config and 5-second recurring schedule in `backend/config/sidekiq.yml`
- [ ] T057 [US1] Flush job spec covering batch atomicity and counter accuracy in `backend/spec/jobs/clicks/flush_job_spec.rb`
- [ ] T058 [US1] `after_commit` cache invalidation on `Link` in `backend/app/models/link.rb` (Principle IV, D2)
- [ ] T059 [US1] Run the identical k6 script against the cached build and commit `load/results/cached.json`
- [ ] T060 [US1] Enumeration script in `load/enumerate.js` and verification that absent codes produce flat Postgres load (SC-007)
- [ ] T061 [US1] Stampede verification in `load/stampede.js` (referenced from quickstart.md): delete a hot key, drive 500 VUs, assert roughly one Postgres query rather than 500 (D5)

**Checkpoint 3C**: US1 complete. SC-001, SC-002, SC-004, SC-005, SC-007 measurable. **This is the MVP.**

---

## Phase 4: User Story 2 - See whether the post worked (Priority: P2)

**Goal**: The creator sees how many people opened each of their links.

**Independent Test**: Create a link, open it N times, confirm the dashboard reports N within 30 seconds.

- [ ] T062 [P] [US2] Link serializer exposing `clicks_count` and `short_url` in `backend/app/serializers/link_serializer.rb` per the `Link` schema
- [ ] T063 [US2] `Api::V1::LinksController#index` with pagination and owner scoping in `backend/app/controllers/api/v1/links_controller.rb` (FR-002, FR-023)
- [ ] T106 [US2] `Api::V1::LinksController#show` with owner scoping, returning 404 rather than 403 for another account's link, in `backend/app/controllers/api/v1/links_controller.rb` (contracts/openapi.yaml `/links/{id}` GET; needed by the edit form in T080)
- [ ] T064 [US2] Request spec asserting account B never sees account A's links in `backend/spec/requests/api/v1/links_isolation_spec.rb` (FR-002)
- [ ] T065 [US2] Integration test asserting the counter reaches N within 30 seconds of the last click in `backend/spec/integration/click_counting_spec.rb` (SC-009)
- [ ] T066 [US2] Integration test asserting redirects still succeed with Redis stopped in `backend/spec/integration/redis_outage_spec.rb` (SC-008)
- [ ] T067 [P] [US2] Typed API client in `frontend/src/lib/api.ts` — holds the access token in memory, sends `Authorization: Bearer`, and on a `token_expired` 401 refreshes once through the BFF and retries the original request exactly once (D10)
- [ ] T118 [US2] BFF route handlers in `frontend/src/app/api/auth/` — sign-in, sign-out, and refresh proxied to Rails, with the refresh token kept in an httpOnly cookie on the Next.js origin and never returned to the browser (D10)
- [ ] T068 [P] [US2] Sign-up and sign-in pages in `frontend/src/app/(auth)/`, posting to the BFF handlers from T118 rather than to Rails directly (design.md §6.2 — note the single indistinguishable failure message required by FR-036)
- [ ] T107 [P] [US2] TanStack Query provider scoped to the dashboard segment in `frontend/src/app/(dashboard)/providers.tsx` — used for click-count polling only, not as the app's data layer (D15)
- [ ] T122 [P] [US2] Shared presentation components from design.md §7 — `<ShortLink>`, `<CopyButton>`, `<ClickCount>`, `<EmptyState>` — in `frontend/src/components/`, with component tests for the two-second copy success swap and for the tabular-figure column holding width across 0, 8, and 4051 (design.md P2, P3, P4)
- [ ] T069 [US2] Link list page showing short URL, destination, created date, click count in `frontend/src/app/(dashboard)/links/page.tsx` — table columns, hover, skeleton, empty, error, and pagination per design.md §6.3, built from T122's components
- [ ] T108 [US2] Poll click counts on a 30-second `refetchInterval` in `frontend/src/app/(dashboard)/links/use-links.ts` (SC-009) — background refetches change the number and nothing else, per design.md P4
- [ ] T070 [US2] Link creation form with one-click copy in `frontend/src/app/(dashboard)/links/new/page.tsx` — react-hook-form + zod, mapping all six server `error.code` values to field-level errors. Copy for all six, plus the in-place success panel, is fixed in design.md §6.4
- [ ] T071 [P] [US2] Component tests for the list and create form in `frontend/tests/`

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 - Fix a mistake without reprinting the poster (Priority: P3)

**Goal**: The creator changes where a link points, or removes it, without the short code changing.

**Independent Test**: Create a link, open it, change the destination, open it again — the second open lands on the new destination.

- [ ] T072 [P] [US3] Model spec asserting `code` cannot be updated in `backend/spec/models/link_immutability_spec.rb` (FR-026)
- [ ] T073 [US3] Guard against `code` reassignment in `backend/app/models/link.rb`
- [ ] T074 [US3] `Links::Updater` in `backend/app/services/links/updater.rb` — re-runs SSRF and blocklist validation on the new destination, invalidates cache via `after_commit` (FR-025, FR-027)
- [ ] T075 [US3] `Api::V1::LinksController#update` returning 422 when `code` is present in the body in `backend/app/controllers/api/v1/links_controller.rb`
- [ ] T076 [US3] `Links::Destroyer` soft delete in `backend/app/services/links/destroyer.rb` — sets `deleted_at`, invalidates cache, retains statistics, never releases the code (FR-028, FR-029, D12)
- [ ] T077 [US3] `Api::V1::LinksController#destroy` in `backend/app/controllers/api/v1/links_controller.rb`
- [ ] T078 [US3] Request spec asserting another account's update and delete both return 404, not 403 in `backend/spec/requests/api/v1/links_ownership_spec.rb` (FR-002)
- [ ] T079 [US3] **Integration test for SC-006**: populate cache, edit destination, assert the very next request follows the new destination with no TTL wait, in `backend/spec/integration/cache_invalidation_spec.rb` (Principle IV — this is the build-blocking test)
- [ ] T080 [P] [US3] Link edit form in `frontend/src/app/(dashboard)/links/[id]/edit/page.tsx` with the code field rendered read-only, reusing the zod schema from T070 (design.md §6.5 — a read-only code row, not a disabled input)
- [ ] T081 [P] [US3] Delete action with confirmation in `frontend/src/app/(dashboard)/links/[id]/page.tsx` — dialog copy stating the retention and 30-day reservation rules per design.md §6.6

**Checkpoint**: All creator-facing stories independently functional.

---

## Phase 6: User Story 4 - Keep the platform clean (Priority: P4)

**Goal**: The administrator finds reported links and bans them or their owning accounts.

**Independent Test**: Report a link, find it in the admin queue, ban it, confirm the next visitor sees the warning page.

- [ ] T082 [P] [US4] `AdminAuthorization` controller concern in `backend/app/controllers/concerns/admin_authorization.rb` (FR-003)
- [ ] T083 [P] [US4] Request spec asserting a creator gets 403 on every `/admin/*` path in `backend/spec/requests/api/v1/admin/authorization_spec.rb`
- [ ] T084 [P] [US4] Safety warning page with report control in `backend/app/views/pages/banned.html.erb` (FR-018) — layout, report control, and CSS subset per design.md §6.9 and §8
- [ ] T085 [US4] Anonymous `POST /:code/report` endpoint with per-IP-hash rate limiting and no reporter identity stored in `backend/app/controllers/reports_controller.rb` (FR-033, Principle V)
- [ ] T086 [P] [US4] `Admin::LinksController#index` trigram search by code or destination in `backend/app/controllers/api/v1/admin/links_controller.rb` (FR-030)
- [ ] T087 [US4] `Admin::LinksController#ban` with immediate cache invalidation in `backend/app/controllers/api/v1/admin/links_controller.rb` (FR-031)
- [ ] T110 [US4] Maintain `account:<id>:codes` on the cache-miss populate path in `backend/app/services/cache/link_cache.rb` — `SADD` plus 24h `EXPIRE`, miss path only so the hot path stays at one `GETEX` (research.md D14)
- [ ] T088 [US4] `Admin::AccountsController#ban` invalidating every cached link via `SMEMBERS` + pipelined `DEL` over `account:<id>:codes`, never `SCAN`, in `backend/app/controllers/api/v1/admin/accounts_controller.rb` (FR-031, D14)
- [ ] T089 [US4] Spec asserting an account ban takes effect on the next visitor for all its links, with no TTL wait, in `backend/spec/requests/api/v1/admin/account_ban_spec.rb` (Principle IV)
- [ ] T119 [US4] Spec asserting a banned account's refresh tokens are all revoked and that its access token stops working within `Auth::AccessToken::LIFETIME`, in `backend/spec/requests/api/v1/admin/account_ban_spec.rb` — the recorded D10 window, asserted rather than assumed
- [ ] T109 [P] [US4] `Admin::ReportsController#index` with status filter, oldest first, in `backend/app/controllers/api/v1/admin/reports_controller.rb` (FR-033; the queue page in T094 has nothing to call without it)
- [ ] T090 [P] [US4] `Admin::BlockedDomainsController` index and create in `backend/app/controllers/api/v1/admin/blocked_domains_controller.rb` (FR-032)
- [ ] T091 [US4] Wire the blocklist check into `Links::Creator` and `Links::Updater` (FR-007)
- [ ] T092 [US4] `Admin::HealthController#show` returning cache hit ratio, redirect p50/p99, redirects per second, click buffer depth, flush lag, Redis memory in `backend/app/controllers/api/v1/admin/health_controller.rb` (FR-035)
- [ ] T093 [US4] Spec asserting `/admin/health` exposes no customer marketing analytics in `backend/spec/requests/api/v1/admin/health_spec.rb` (FR-034, Principle V)
- [ ] T094 [P] [US4] Admin moderation queue page in `frontend/src/app/admin/reports/page.tsx` — inline ban actions and no clicks column, per design.md §6.7 (SC-010, FR-034)
- [ ] T095 [P] [US4] Admin link search, accounts, and health pages in `frontend/src/app/admin/` (design.md §6.8)

**Checkpoint**: All four user stories independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Note**: There is no lint-cleanup task here. Linting moved to Phase 1 (T099) and is a
blocking CI check from PR 1, so style debt never accumulates to be cleaned up.

- [ ] T096 [P] Daily 7-day click purge job in `backend/app/jobs/clicks/purge_job.rb` (data-model.md retention rule)
- [ ] T097 Run the full `quickstart.md` procedure end to end and correct any drift
- [ ] T111 Timed walkthroughs recorded in `load/results/usability.md`: an unaided first-time user creating their first link (SC-003, target under 2 minutes) and an administrator locating and banning a reported link (SC-010, target under 1 minute)
- [ ] T098 [P] Playwright end-to-end test covering register → create → redirect → count in `frontend/tests/e2e/`
- [ ] T100 Security review of `backend/app/services/urls/safety_validator.rb` against a fresh bypass list, and of the token surface: algorithm pinning, claim validation, refresh rotation, and the BFF cookie flags
- [ ] T101 Re-run both load tests on final code and refresh `load/results/`
- [ ] T102 Write `README.md` leading with the naive-versus-cached numbers and the twelve explainable decisions from spec.md section 10
- [ ] T103 Verify every Constitution Check gate in `specs/001-url-shortener-mvp/plan.md` still passes against the built system, recording the result in `load/results/constitution-check.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies
- **Phase 2 (Foundational)**: depends on Phase 1 — **blocks all user stories**
- **Phase 3 (US1)**: depends on Phase 2. Internally strictly ordered 3A → 3B → 3C
- **Phase 4 (US2)**: depends on Phase 3C (needs the buffered click pipeline to have a counter worth reading)
- **Phase 5 (US3)**: depends on Phase 3C (SC-006 is meaningless without a cache to invalidate)
- **Phase 6 (US4)**: depends on Phase 2; independent of US2 and US3, though T087–T089 need the cache from 3C
- **Phase 7 (Polish)**: depends on all desired stories

### The one hard ordering constraint

3A → 3B → 3C is not a preference. 3B measures something that ceases to exist once 3C lands. `REDIRECT_CACHE_ENABLED` keeps the naive path runnable afterwards, but the *first* measurement must be taken against a build that has no cache code in it at all — otherwise the baseline is measuring a disabled optimisation rather than an unoptimised system.

### Parallel Opportunities

- Phase 1: T003, T005, T006, T008, T010, T099, T104 all parallel; T007 (CI) runs after T099
- Phase 2: T011, T012, T014, T015, T016, T017, T019, T020, T021 all parallel (T013 alone, since links is the busiest schema); T120 and T123 parallel with all of them, T121 after both
- Phase 3A: T023–T026 (specs) parallel; T028, T029, T030 parallel; T037 parallel
- Phase 3C: T045–T048 parallel, then T049–T061 largely sequential on the middleware file
- Phase 4: backend (T062–T066) and frontend (T067–T071, T122) parallel across two people; T122 before T069 and T070
- Phase 6: T082, T083, T084, T086, T090, T094, T095 parallel

---

## Implementation Strategy

### Pull request boundaries

One PR per phase, seven PRs plus polish. Not one per task.

| PR | Phase | Tasks | Demonstrable at merge |
|---|---|---|---|
| 1 | Setup | T001–T010, T099, T104 | stack runs, suites green, linters blocking |
| 2 | Foundational | T011–T022, T114, T115, T120, T121, T123 | schema migrates, models load, bearer auth verified, canvas published, shell renders in both themes |
| 3 | US1 / 3A | T023–T039, T105, T116, T117 | links create and redirect, slowly |
| 4 | US1 / 3B | T040–T044 | **a committed baseline number** |
| 5 | US1 / 3C | T045–T061 | the same test, a different number |
| 6 | US2 | T062–T071, T106–T108, T118, T122 | dashboard with live counts |
| 7 | US3 | T072–T081 | edit takes effect immediately |
| 8 | US4 | T082–T095, T109, T110, T119 | moderation works |
| 9 | Polish | T096–T098, T100–T103, T111 | README with the headline result |

PR 4 contains no application code. It will look like a trivial PR and it is the most important one in the sequence.

PR 3 and PR 4 bodies MUST carry the Principle I waiver recorded in plan.md: the naive redirect knowingly violates it, scoped to T035–T044 and expiring at T045.

Per the constitution, each PR body states which FR-xxx it satisfies and which SC-xxx it moves.

### MVP scope

**Phases 1 → 2 → 3 (all sub-phases).** That is PRs 1–5, ending with a working shortener and both load-test numbers committed. US2, US3, and US4 are each a standalone increment on top.

### Incremental delivery

Stop after any checkpoint and the system is coherent. Stopping mid-Phase-3 is the one exception: 3A alone is a shortener that falls over under load, and 3B alone is a measurement of something you are about to delete.
