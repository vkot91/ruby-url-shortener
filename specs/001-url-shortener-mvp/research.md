# Phase 0 Research: URL Shortener MVP

**Date**: 2026-08-26 | **Plan**: [plan.md](./plan.md)

No `NEEDS CLARIFICATION` markers remained in the Technical Context. The items below are the
decisions that carry risk, each recorded with what was rejected.

---

## D1. Redirect served by Rack middleware, not a Rails controller

**Decision**: A `RedirectMiddleware` inserted before `ActionDispatch::Session` and the Rails router
matches `GET /:code`, resolves from Redis, and returns a 302 Rack triple directly.

**Rationale**: Principle I forbids non-essential synchronous work on the redirect path. A Rails
controller action drags in session loading, cookie parsing, CSRF setup, ActiveRecord object
allocation, and view lookup — none of which a redirect needs. Middleware skips all of it. This is
also the single largest lever on SC-004; the remaining stack is roughly Puma → Rack → Redis GET.

**Alternatives considered**:
- *Standard Rails controller*: simplest, but middleware costs one file and removes most of the
  per-request work. Rejected on measurement grounds, to be confirmed in Phases 3B/3C.
- *Separate Go or Rust redirect service*: fastest, but introduces a second language, a second
  deployment, and duplicated cache logic for a benchmark that is not the point. Rejected as
  premature under the constitution's simplicity clause.
- *Nginx + Redis module doing the lookup*: removes Ruby entirely, but the expiry, ban, and click
  buffering rules would have to live in Lua. Rejected — moves product logic into infrastructure.

## D2. `after_commit` invalidation, not in-transaction invalidation

**Decision**: Cache deletion fires in an `after_commit` callback on `Link`, before the controller
returns its response.

**Rationale**: Principle IV requires invalidation to happen inside the same operation and before
acknowledgement — not that it happen inside the database transaction. Deleting the key *during* the
transaction is actively wrong: a concurrent reader can miss, read the not-yet-committed old row,
and repopulate the cache with stale data that then lives for 24 hours. `after_commit` closes that
window. The residual risk is a crash between commit and delete, which is bounded by the TTL and is
detectable; the in-transaction version's failure mode is silent and long-lived.

**Alternatives considered**:
- *Delete inside the transaction*: rejected for the repopulation race above.
- *Write-through — update the cache with the new value instead of deleting*: rejected. Delete is
  idempotent and cannot serve a partially-updated value; write-through has its own ordering races
  between concurrent updates.
- *Rely on the 24h TTL*: rejected outright by Principle IV. This is the defect the principle exists
  to prevent.

## D3. Code allocation by insert-and-rescue

**Decision**: Generate 7 characters from a 62-character alphabet using `SecureRandom`, insert, and
rescue `ActiveRecord::RecordNotUnique` with a retry (bounded at 5 attempts).

**Rationale**: Principle III. A `SELECT` followed by an `INSERT` has a window between them that
concurrency will find. 62^7 ≈ 3.5×10^12 possibilities means collisions are vanishingly rare at MVP
scale, so the retry path is nearly dead code — which is the point: correctness costs nothing here.
Random rather than sequential because sequential codes are enumerable by anyone who wants a list of
every link on the platform.

**Alternatives considered**:
- *Sequential ID encoded to base62*: shorter codes, no collisions at all, and a free ordering. Rejected
  — the entire corpus becomes walkable from the outside, which is a privacy failure for customers
  who assume an unlisted link is unlisted.
- *Pre-generated code pool table*: removes retries entirely but adds a table, a refill job, and a
  new class of operational failure (pool exhaustion). Rejected as unjustified machinery.

## D4. Clicks buffered in a Redis list, drained in batches

**Decision**: The middleware issues `LPUSH clicks:buffer <link_id>:<timestamp>`. A Sidekiq worker
runs every 5 seconds, does `LPOP clicks:buffer 1000`, bulk-inserts the rows, and increments each
link's counter in one grouped `UPDATE`.

**Rationale**: One `INSERT` per redirect makes Postgres the throughput ceiling and couples visitor
latency to database health, violating Principle I. `LPOP key count` (Redis 6.2+) pops atomically, so
two workers cannot process the same batch. Losing an in-flight batch on a crash costs seconds of
statistics — explicitly acceptable per the constitution's durability ordering.

**Alternatives considered**:
- *Redis Streams with consumer groups*: gives acknowledgement and replay of unprocessed entries.
  Genuinely better durability, but adds consumer-group management and pending-entry recovery for a
  data class the constitution says is expendable. Rejected as over-built for MVP; noted as the
  upgrade path if click loss ever becomes a complaint.
- *`INSERT` per click, async via Sidekiq*: still one row and one job per click. Moves the load
  rather than reducing it. Rejected.
- *Counter-only, no raw rows*: cheapest, but forecloses the per-click dimensions (country, device,
  referrer) the paid tier is built on. Rejected — it would require a redesign at the first paid feature.

## D5. Single-flight cache rebuild

**Decision**: On a miss, a request attempts `SET lock:<code> 1 NX EX 5`. The winner queries Postgres
and populates the cache; losers retry the cache read briefly, then fall through to Postgres
themselves after the lock's grace period.

**Rationale**: Directly answers the spec's viral-link-at-expiry edge case and SC-007. Without it, a
hot key expiring produces one Postgres query per concurrent request — the exact stampede that takes
the database down at peak.

**Alternatives considered**:
- *Probabilistic early expiration (XFetch)*: elegant and lock-free, but harder to reason about and
  to demonstrate in the write-up. Rejected on explainability, which is a stated project goal.
- *Never expire, invalidate only on write*: removes stampedes entirely, but unbounded growth in
  Redis and no self-healing if an invalidation is ever missed. Rejected.
- *Nothing*: rejected — SC-007 is a stated success criterion.

## D6. TTL refreshed on read via `GETEX`

**Decision**: The cache read is `GETEX link:<code> EX 86400`, one round trip that both fetches and
extends.

**Rationale**: A fixed 24h TTL from write time means a link that is popular for 24 hours expires
exactly when it is hottest. Refresh-on-read makes eviction reflect actual coldness. `GETEX` avoids a
second round trip on the hot path, which matters at 5 000 rps.

**Alternatives considered**: separate `GET` + `EXPIRE` (doubles hot-path round trips); relying on
`maxmemory-policy allkeys-lru` alone without TTL (loses the negative-cache expiry semantics).

## D7. Negative caching with a sentinel

**Decision**: A code confirmed absent in Postgres is cached as the literal string `__404__` with a
60-second TTL, checked before the value is parsed as a URL.

**Rationale**: FR-017 and SC-007. Enumeration of random 7-character codes is expected traffic for
any shortener; without negative caching each attempt is a Postgres query. A sentinel keeps one code
space rather than requiring a parallel "known-absent" key namespace.

**Alternatives considered**: a Bloom filter (better memory profile at scale, but deletions and false
positives complicate correctness for a problem 60-second TTLs already solve); no negative caching
(rejected by SC-007).

## D8. 302 with `Cache-Control: no-store`

**Decision**: Redirects are 302 Found with `Cache-Control: no-store` and no `Location` caching hints.

**Rationale**: FR-016. A 301 is cached by browsers and intermediaries, sometimes indefinitely, which
would make destination editing — the product's core promise per US3 — silently fail for exactly the
visitors who clicked before the edit. The SEO argument for 301 does not apply: the destination, not
the short link, is what should rank.

**Alternatives considered**: 301 (rejected, breaks US3); 307/308 (correct method-preservation
semantics but no benefit for a GET-only path, and 308 is permanently cached like 301).

## D9. Sidekiq rather than Solid Queue

**Decision**: Sidekiq 7 on the existing Redis instance, in a dedicated Redis database index.

**Rationale**: Rails 8's default Solid Queue is Postgres-backed. The entire architecture exists to
keep load off Postgres; routing the click-flush job — the highest-frequency job in the system —
through Postgres would add write load proportional to click volume, which is precisely what D4
removes. Redis is already a hard dependency, so Sidekiq adds a gem, not a service.

**Alternatives considered**:
- *Solid Queue*: fewer moving parts and no extra gem, but contradicts the read/write separation the
  project is about. Rejected.
- *A plain loop in a rake task*: fewer dependencies still, but no retries, no concurrency control,
  no visibility. Rejected — the flush job is on the correctness path for customer-visible numbers.

## D10. JWT access tokens with opaque rotating refresh tokens

**Status**: Supersedes the original D10 ("Session cookies, not JWT"), which is preserved below.

**Decision**: Bearer-token authentication. A short-lived JWT access token (HS256, 15 minutes,
claims `sub`/`role`/`jti`/`iat`/`exp`) is verified by signature alone and sent as
`Authorization: Bearer`. Refresh is an opaque 32-byte random token — deliberately *not* a JWT —
stored as a SHA-256 digest in `refresh_tokens`, rotated on every use, grouped into a family per
sign-in, with reuse detection revoking the family. Rails sets no cookie at all; the Next.js BFF
holds the refresh token in an httpOnly cookie on its own origin.

**Rationale**: Four drivers, all of which the original decision failed to serve:

1. *Non-browser clients.* A mobile app or CLI is a stated future client, and cookie sessions serve
   them badly. A bearer token is the same credential for every client type.
2. *Demonstrable correctness.* Refresh rotation with reuse detection is a thing this project sets
   out to build properly. Rotation without detection changes the token but notices nothing when a
   copy is used behind your back.
3. *Stateless verification.* An authenticated API request touches neither Postgres nor Redis. The
   claims are the proof, and `current_account` is loaded lazily so only endpoints that need the row
   pay for it.
4. *Cross-origin friction.* Frontend and API are separate origins; a header sidesteps the
   `SameSite`/CORS negotiation a session cookie requires.

**The cost, accepted explicitly**: revocation is no longer instant. A ban revokes every refresh
token of that account immediately, but an already-issued access token keeps working until it
expires — up to 15 minutes. The same window applies to a role change, since `role` is a claim.

This is a real trade and it is taken deliberately:

- It does not touch FR-031. That requirement is about the *visitor* on the redirect path, which is
  served by cache invalidation (D2, D14) and is unaffected by how creators authenticate.
- The residual exposure is a banned creator retaining API access for one access-token lifetime.
  Shortening the lifetime narrows it at the cost of refresh round trips.
- The alternative — a Redis denylist consulted on every authenticated request — was considered and
  rejected. It would restore instant revocation at roughly no latency cost, since Principle I
  protects only the redirect path and the API can afford a Redis GET. It was rejected because it
  abandons driver 3 while looking like it does not, and a stateless design that quietly checks
  state on every request is worse than either honest option.

`spec/requests/foundation_spec.rb` asserts this window rather than assuming it: a spec proves an
authenticated request issues no query, and another proves a token issued before a ban still works.
If someone later adds a per-request revocation check, those specs fail and force the decision back
into the open rather than letting it drift.

**Alternatives considered**:
- *Refresh token as a second JWT*: nothing about a refresh token benefits from being
  self-describing, and an opaque token cannot leak claims to whoever holds it. Rejected.
- *Refresh token in JS-reachable storage*: survives page reload, but hands long-lived credentials to
  any XSS. Rejected in favour of the BFF.
- *A dedicated `JWT_SECRET`*: rejected. The signing key is derived from `secret_key_base` via
  `ActiveSupport::KeyGenerator`, so there is one secret to configure and one to rotate.

### Superseded: D10 (original) — Session cookies, not JWT

Retained because the constitution requires a reversed decision to keep its original reasoning
visible, so the reversal can be judged rather than merely noticed.

**Decision was**: Rails 8 built-in authentication (`has_secure_password` + sessions table), httpOnly
`Secure` `SameSite=Lax` cookie on the app domain. Next.js calls the API with `credentials: include`.

**Rationale was**: Simplest correct option. Server-side revocation is a `DELETE` on a row, which the
admin account-ban feature (FR-031) needs anyway. No token refresh machinery, no storage of
credentials in JavaScript-reachable places.

**Why it was reversed**: its rejection of JWT rested on revocation cost, and it was right that
revocation is where JWT hurts. What it did not weigh was that the project has non-browser clients
ahead of it and that FR-031's guarantee is about visitors, not creators — so the revocation it was
protecting was never the one the requirement asked for.

## D11. SSRF validation resolves DNS before accepting a destination

**Decision**: `Urls::SafetyValidator` parses the URL, rejects non-http(s) schemes, resolves the
hostname, and rejects any address in a private, loopback, link-local, or reserved range, plus the
service's own domains. Re-validated on destination edit, not only on creation.

**Rationale**: FR-006. Checking the hostname string alone is defeated by a domain whose A record
points at `169.254.169.254` or `127.0.0.1`. The redirect itself is client-side, so the primary risk
is using the service as an SSRF probe against internal infrastructure and as an open proxy.

**Known limit**: DNS can change between validation and use (TOCTOU). This is not fully solvable for
a redirector, since the fetch happens in the visitor's browser rather than on the server. Recorded
here as an accepted residual risk rather than a solved problem.

**Alternatives considered**: hostname string denylist only (trivially bypassed); no validation
(rejected — this is an input-validation trust boundary, out of scope for simplification).

## D12. Deleted codes are never reused in MVP

**Decision**: Soft-deleted links keep their row and their code. The unique index therefore keeps the
code permanently occupied, and random generation retries past it via D3.

**Rationale**: FR-029 requires a code be unavailable for *at least* 30 days. Never releasing it
satisfies that with zero machinery — no quarantine table, no expiry job, no reclamation race. MVP
has no custom codes, so nobody can ask for a specific released code anyway. The 3.5×10^12 code space
makes exhaustion irrelevant.

**Revisit when**: custom codes ship (Pro tier), at which point a customer may legitimately want to
reclaim their own deleted `/black-friday`. That is when the 30-day quarantine becomes real logic.

## D13. Reference environment for the load test

**Decision**: One host, Docker Compose, all services co-resident, fixed corpus of 10 000 links with
a Zipf-distributed access pattern in the k6 script.

**Rationale**: Principle II requires the naive and cached runs to differ only in the code under
test. Co-residency removes network variance; a fixed seeded corpus removes data variance; a Zipf
distribution rather than uniform random makes the cache-hit ratio meaningful, since uniform access
across a large corpus would understate cache value in a way real traffic never does.

**Alternatives considered**: uniform random access (misrepresents both versions); production-like
multi-host (introduces variance unrelated to the change being measured).

---

## D14. Account-ban invalidation via a per-account code set

**Raised by**: `/speckit-analyze` finding U1 — banning an account must invalidate every cached link
it owns, but `link:<code>` is keyed by code alone and offers no way to enumerate an account's keys.

**Decision**: When the miss path populates `link:<code>`, it also issues
`SADD account:<id>:codes <code>` and `EXPIRE account:<id>:codes 86400`. Banning an account reads the
set with `SMEMBERS` and pipelines a `DEL` for each code, then deletes the set.

**Rationale**: The extra write lands on the *miss* path only, which is the 1–5% of requests already
paying for a Postgres read. The hot path stays at exactly one `GETEX` (Principle I). Stale members —
codes whose `link:` key has since been evicted — cost one wasted `DEL` each and are otherwise
harmless, so the set needs no reconciliation job. The 24-hour expiry bounds its growth.

**Alternatives considered**:
- *`SCAN` the keyspace on ban*: O(keyspace) with 500 000 links, and `SCAN` under 5 000 rps of
  concurrent traffic is exactly the operation Redis documentation warns about. Rejected.
- *Cache the account-banned flag under its own key and check it on every redirect*: correct and
  simple, but adds a second Redis round trip to 100% of redirects to serve a condition that applies
  to a fraction of a percent of them. Rejected under Principle I.
- *Write `banned` into every cached link row at ban time by re-reading the account's links from
  Postgres*: works, and is O(links owned) rather than O(keyspace), but does a Postgres read plus a
  write per link inside an admin request. Acceptable fallback if the set proves fiddly; the set is
  cheaper and does not touch Postgres.

**Known limit**: an account ban issued while Redis is down will not invalidate anything. The links
still resolve correctly once Redis returns, because the miss path re-reads the account's `banned_at`
from Postgres. Worst case is up to 24 hours of stale cached entries for that account — noted, not
solved, and detectable via the admin health endpoint.

### Amendment (2026-09-03): the set expires out from under the keys it names

The rationale above reasons about stale *members* — codes whose `link:` key has been evicted — and
concludes they cost one wasted `DEL`. It does not reason about the stale *set*, and that is the case
that matters.

The two TTLs are refreshed by different events. `link:<code>` is read with `GETEX` (D6), so every
request extends it. `account:<id>:codes` is written only by `LinkCache.write`, which runs only on a
miss. A code that never misses again therefore keeps its cached entry alive indefinitely while its
membership record expires 24 hours after the last miss.

The failing sequence:

1. `T0` — a link is cached on a miss; the set is written with a 24-hour expiry.
2. `T0 .. T0+25h` — the link is read continuously. Each read pushes `link:<code>` out another 24
   hours. No miss occurs, so nothing touches the set.
3. `T0+24h` — `account:<id>:codes` expires.
4. `T0+25h` — the account is banned. `SMEMBERS` returns empty. No `DEL` is issued.
5. The link keeps redirecting until its own traffic stops for 24 hours.

So the invalidation fails precisely for an account's *hottest* links, which for a ban issued over
abuse is the worst subset to miss. This is a correctness hole in the ban, not a performance note.

**Resolution**: at ban time the authority is Postgres, not the set —
`Link.where(account_id:).pluck(:code)` and a pipelined `DEL` over the result. That is the third
alternative listed above, which was kept as an "acceptable fallback if the set proves fiddly". It
has proved fiddly.

Once the ban reads Postgres, the set adds nothing to correctness and only bounds the number of `DEL`
commands — from O(links owned) to O(links cached). That bound is not worth buying: a pipelined `DEL`
of even 500 000 keys is well under a second, inside an admin operation performed rarely, and it is
paid in Redis rather than on the redirect path. **The recommendation is therefore to drop
`account:<id>:codes` entirely** and let the ban enumerate from the system of record.

Refreshing the set's TTL on read was considered and rejected: it puts a second Redis command on
100% of redirects to serve a condition that applies to a fraction of a percent of them, which is the
same trade Principle I already rejected in the second alternative above.

**Status**: recorded, not yet applied. `Cache::LinkCache.write` still issues the `SADD`/`EXPIRE`, and
the consumer does not exist — the account ban is Phase 6 (T084 and its neighbours). The removal
belongs in the same change that writes the ban, so that the set and the code that would have read it
disappear together rather than leaving one without the other.

## D15a. pnpm as the frontend package manager

**Decision**: pnpm, pinned by the `packageManager` field in `frontend/package.json` and activated
through corepack. `pnpm-lock.yaml` is the committed lockfile; `package-lock.json` is removed.

**Rationale**: shadcn/ui copies components into the tree and pulls a wide Radix dependency graph, so
the content-addressed store saves meaningful disk and install time on every rebuild of the dev image.
The strict, non-flat `node_modules` also refuses undeclared transitive imports, which is the failure
this project would otherwise only discover in a production build.

**Applies to**: the local `pnpm dev` workflow (`corepack enable`, `pnpm install --frozen-lockfile`)
and both frontend CI jobs via `pnpm/action-setup`. The dev image this originally also covered is
gone — the frontend runs natively, see quickstart.md.

---

## D15. Frontend library selection

**Decision**: shadcn/ui, zod, react-hook-form, and TanStack Query — the last one scoped to polling
the dashboard click counts and nothing else.

**Rationale**: The MVP frontend is four forms and five tables. shadcn/ui is copied into the tree
rather than installed, so accessible dialog, table, and toast primitives arrive without a runtime
dependency or owning the focus-trap work (the constitution names accessibility basics as
non-simplifiable). zod earns its place because link creation has six distinct server rejection codes
that must map to field-level errors, and the same schemas type the API client's responses.

TanStack Query is deliberately narrow. SC-009 permits 30 seconds of staleness in the click counter,
so the link list needs polling; `refetchInterval` is one line against a hand-rolled effect, timer,
cleanup, and tab-visibility check. Routing the rest of the app through it would mean opting out of
React Server Components — which fetch directly on the server — for no benefit.

**Alternatives considered**:
- *A client state manager (Zustand, Redux)*: rejected. There is no client state. The session is an
  httpOnly cookie and everything else is server data.
- *A charting library*: rejected. MVP renders one integer per link; charts belong to the paid
  analytics tier, which is out of scope.
- *Plain `fetch` with no query library at all*: viable, and was the original plan. Rejected only for
  the polling case above.
