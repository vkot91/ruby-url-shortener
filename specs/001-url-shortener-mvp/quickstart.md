# Quickstart: Validating the URL Shortener MVP

**Date**: 2026-08-26 | **Plan**: [plan.md](./plan.md)

How to run the stack and prove each user story works. This is a validation guide, not an
implementation guide — code belongs in `tasks.md` and the implementation phases.

## Prerequisites

- Docker and Docker Compose — for Postgres and Redis only
- Ruby 3.4 (`asdf install ruby 3.4.8`; pin it with a `.tool-versions` in Phase 1 (task T001) — the repo has none yet)
- Node 24 LTS, with pnpm enabled via `corepack enable` — the frontend uses pnpm, not npm, and the
  version is pinned by `packageManager` in `frontend/package.json`
- k6, for Phases 3B and 3C only

## Bring the stack up

Postgres and Redis run in containers; the Rails server, Sidekiq, and the Next.js dev server run
natively. Copy both environment templates first — nothing in the codebase carries a default, so an
unset name fails at boot:

```bash
cd backend  && cp .env.example .env
cd frontend && cp .env.example .env.local
```

`backend/.env` is read twice: by compose, for the two service definitions, and by the Rails app
through `dotenv-rails` in development and test. There is nothing to source by hand. Next.js loads
`.env.local` on its own.

```bash
cd backend && docker compose up -d          # postgres + redis, nothing else
cd backend && bin/rails db:prepare          # loads spec/fixtures on first create
cd backend && bin/rails s                   # port 3001, set in config/puma.rb
cd backend && bundle exec sidekiq           # separate shell
cd frontend && pnpm dev                     # separate shell, port 3000
```

Two hosts in development, matching the production split: `localhost:3001` is the short domain and
API, `localhost:3000` is the dashboard.

Running the application natively rather than in compose is deliberate. It is what CI already does
(`.github/workflows/ci.yml` uses `ruby/setup-ruby` against service containers), it puts the debugger
and the test runner in the same process as the code, and it removes the failure where a
`Gemfile.lock` edited on the host stops matching the gems baked into an image.

Health check: `curl -sf localhost:3001/up` returns 200.

### The development dataset

`spec/fixtures/*.yml` is the one description of it, shared by `db:seed`, by
`bin/rails db:fixtures:load`, and by any spec that opts in. Reload it whenever
you want a known state back:

```bash
cd backend && bin/rails db:fixtures:load
```

Not additive — every table the fixtures cover is emptied and refilled, so this
discards anything you created by hand. Four accounts (`dev`, `admin`, `rival`,
`suspended` — all at `@snip.test`, all with the password `development password`)
and seven links covering every outcome `GET /:code` has to resolve:

| Code | State | Expected |
|---|---|---|
| `aa1bb2c` | ordinary | 302 to the destination |
| `pop9lar` | 7 clicks behind it | 302, and a non-zero counter to read |
| `gone404` | soft-deleted | 404, `clicks_count` survives (FR-028) |
| `bad1234` | banned link | warning page (FR-018) |
| `susp3nd` | clean link, banned owner | warning page, from the account's state |
| `riv4l99` | owned by `rival` | invisible to `dev` (FR-002) |
| `dup7lic` | same destination as `aa1bb2c` | its own code and counter (FR-011) |

Also loaded: three reports, one per moderation status; two blocked domains; and
five refresh tokens covering live, rotated, expired, and revoked. The raw token
values are the strings they hash from — `dev-refresh-live` and friends, named in
`spec/fixtures/refresh_tokens.yml` — so `/auth/refresh` can be exercised by hand.

## US1 — Shorten a link and share it

```bash
# Register. There is no cookie jar anywhere in this file: authentication is a
# bearer token (research.md D10), and the API sets no cookies on any path.
ACCESS=$(curl -sX POST localhost:3001/api/v1/registrations \
  -H 'Content-Type: application/json' \
  -d '{"email":"oksana@example.com","password":"correct-horse-battery"}' | jq -r .access_token)

# Create
curl -sX POST localhost:3001/api/v1/links \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $ACCESS" \
  -d '{"destination_url":"https://example.com/black-friday","name":"BF campaign"}'

# Redirect — expect 302, the Location header, and no Set-Cookie
curl -si localhost:3001/<code> | head -5
```

**Expected**: `HTTP/1.1 302`, `Location: https://example.com/black-friday`,
`Cache-Control: no-store`, and **no `Set-Cookie` line**. The absent cookie is the assertion, not a
detail — FR-015 and Principle V.

Rejection cases, each expecting 422 with a distinguishing `error.code`:

```bash
for u in "ftp://example.com" "http://127.0.0.1:6379" "http://169.254.169.254/latest/meta-data" "http://localhost:3001/abc123"; do
  curl -sX POST localhost:3001/api/v1/links -H 'Content-Type: application/json' -H "Authorization: Bearer $ACCESS" \
    -d "{\"destination_url\":\"$u\"}" | jq -r '.error.code'
done
# expect: unsupported_scheme, private_address, private_address, self_referential
```

**Deduplication check**: create the same destination from two different accounts. Expect two
different codes and two independent counters (FR-011).

## US2 — See whether the post worked

```bash
for i in $(seq 1 10); do curl -so /dev/null localhost:3001/<code>; done
sleep 10
curl -s localhost:3001/api/v1/links -H "Authorization: Bearer $ACCESS" | jq '.links[0].clicks_count'   # expect 10
```

**Expected**: 10 within 30 seconds (SC-009). The delay is the batch flush, by design (D4).

**Isolation check**: sign in as a second account and list links — the first account's link must not
appear (FR-002).

**Degradation check**: `cd backend && docker compose stop redis`, then request a link. The redirect
must still succeed from Postgres. Only statistics freshness is allowed to suffer (SC-008).

## US3 — Fix a mistake without reprinting the poster

This is the highest-value test in the suite, because it is the one that fails silently in most
implementations.

```bash
curl -so /dev/null localhost:3001/<code>            # populate the cache
curl -sX PATCH localhost:3001/api/v1/links/<id> \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $ACCESS" \
  -d '{"destination_url":"https://example.com/corrected"}'
curl -si localhost:3001/<code> | grep -i '^location'
```

**Expected**: `https://example.com/corrected` on the **very next request** — not after the TTL
expires. If the old destination appears, Principle IV is violated and the build does not ship.

Also verify: `PATCH` with a `code` field returns 422 (FR-026); `DELETE` then request returns 404
while `clicks_count` survives (FR-028); another account's `PATCH` and `DELETE` return 404 (FR-002).

## US4 — Keep the platform clean

```bash
curl -sX POST localhost:3001/<code>/report -H 'Content-Type: application/json' -d '{"reason":"phishing"}'
curl -s localhost:3001/api/v1/admin/reports -H "Authorization: Bearer $ADMIN_ACCESS" | jq
curl -sX POST localhost:3001/api/v1/admin/links/<id>/ban -H "Authorization: Bearer $ADMIN_ACCESS"
curl -si localhost:3001/<code> | head -1        # expect 403 with the warning page
```

**Expected**: 403 on the next request, no TTL wait. A creator account calling any `/admin/*` path
gets 403 (FR-003). `/admin/health` returns operational metrics and **no customer analytics**
(FR-034).

## The load test (Phases 3B and 3C)

The comparison is the project's headline deliverable, so the two runs must differ only in the
subject under test.

```bash
bin/rails runner load/seed.rb                     # fixed 10k-link corpus, deterministic seed

# Restart the server between runs with the flag flipped. It is an environment
# variable read once at boot (config/application.rb), so the process has to come
# back up — editing backend/.env and leaving Puma running measures the old path.
REDIRECT_CACHE_ENABLED=false bin/rails s
k6 run --out json=load/results/naive.json load/redirect.js

REDIRECT_CACHE_ENABLED=true bin/rails s
k6 run --out json=load/results/cached.json load/redirect.js
```

Same host, same corpus, same script, same k6 flags. Only the flag changes.

**Pass conditions**
- Cached run sustains ≥5 000 redirects/second (SC-004)
- p99 service-added latency ≤50 ms (SC-001)
- Cache hit ratio ≥95% (SC-002)
- Availability ≥99.9%, zero wrong destinations (SC-005)

**Also record, for the write-up**: where the naive version broke and why — connection pool
exhaustion, per-request click insert, or query latency. The number alone is half the artifact.

### Stampede and negative-caching checks

```bash
redis-cli -p 6380 DEL link:<hot_code>
k6 run --vus 500 --duration 10s load/stampede.js     # expect ~1 Postgres query, not 500 (D5, SC-007)

k6 run load/enumerate.js                             # random non-existent codes
# expect flat Postgres load after first sighting of each code (D7, SC-007)
```

## Test suites

```bash
cd backend  && bundle exec rspec && bundle exec rubocop
cd frontend && pnpm test && pnpm run lint && pnpm exec playwright test
```

All four are blocking CI checks from PR 1 onward.

The US3 cache-invalidation check above must exist as an automated integration test, not only as a
manual step here — SC-006 names it explicitly.
