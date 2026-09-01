# Data Model: URL Shortener MVP

**Date**: 2026-08-26 | **Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md)

Postgres is the system of record. Redis holds only derived or expendable state and is described in
the second half.

---

## Postgres

### accounts

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `email` | citext | NOT NULL, UNIQUE | case-insensitive uniqueness by column type, not by lowercasing in Ruby |
| `password_digest` | text | NOT NULL | bcrypt via `has_secure_password` |
| `role` | text | NOT NULL, DEFAULT `'creator'`, CHECK IN (`creator`, `admin`) | FR-003 |
| `plan` | text | NOT NULL, DEFAULT `'free'`, CHECK IN (`free`) | only `free` in MVP; column exists so tiers do not need a migration later |
| `banned_at` | timestamptz | NULL | FR-031; NULL means active |
| `created_at` / `updated_at` | timestamptz | NOT NULL | |

**Indexes**: unique on `email`.

**Rules**
- Free accounts are limited to 50 links where `deleted_at IS NULL` (FR-004).
- Link creation is rate-limited per account per hour via Rails' `rate_limit` (FR-004). The counter
  lives in Redis, not in a table — it is expendable.
- Registration and sign-in are rate-limited per hour via the same mechanism (FR-036): by hashed
  origin IP on both endpoints, and additionally by hashed email address on sign-in, so credential
  stuffing cannot be spread across many addresses from one origin.
- Banning an account bans the redirect behaviour of all its links without writing to each link row.

---

### refresh_tokens

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `account_id` | uuid | NOT NULL, FK → accounts, ON DELETE CASCADE | |
| `token_digest` | text | NOT NULL, UNIQUE | SHA-256; the raw token exists only in the client's hands |
| `family_id` | uuid | NOT NULL | one sign-in opens one family; rotation stays inside it |
| `used_at` | timestamptz | NULL | set when exchanged; a token presented with this set is a replay |
| `expires_at` | timestamptz | NOT NULL | 30 days from issue |
| `revoked_at` | timestamptz | NULL | |
| `user_agent` / `ip_address` | text | NULL | the *account holder's*, at sign-in — not a visitor's; Principle V governs the redirect path, not authenticated sessions |
| `created_at` | timestamptz | NOT NULL | |

**Indexes**: unique on `token_digest`; on `family_id`.

**Rules**
- Access tokens are **not** stored. They are JWTs verified by signature, so an authenticated API
  request reads no row at all (D10). This table exists precisely because refresh is the only thing
  that can extend a session, and therefore the only thing that has to be revocable.
- Rotation is mandatory: every exchange stamps `used_at` on the presented token and issues a
  successor in the same family.
- **Reuse detection**: presenting a token that already has `used_at` set means either the client
  replayed itself or somebody else holds a copy. There is no way to tell which, so the entire
  family is revoked and the human signs in again.
- Banning an account revokes every family it owns, fired from the write itself
  (`after_update_commit` on `Account`) rather than from whichever controller applied the ban.
- Revocation of an access token is not possible and not attempted; see D10's recorded window.

---

### links

The central entity. Every column here is on the hot path's critical read, so the row is deliberately
narrow.

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `account_id` | uuid | NOT NULL, FK → accounts | owner; FR-002 |
| `code` | text | NOT NULL, UNIQUE, CHECK length between 3 and 32 | immutable after creation (FR-026) |
| `destination_url` | text | NOT NULL | stored normalised (FR-008) |
| `name` | text | NULL | creator-facing label only |
| `clicks_count` | bigint | NOT NULL, DEFAULT 0 | denormalised counter maintained by the flush job |
| `banned_at` | timestamptz | NULL | FR-031 |
| `deleted_at` | timestamptz | NULL | soft delete (FR-028) |
| `created_at` / `updated_at` | timestamptz | NOT NULL | |

**Indexes**
- `UNIQUE (code)` — this constraint *is* the code-allocation algorithm (D3, Principle III). It is
  not a safety net behind an application-level check; there is no application-level check.
- `(account_id, created_at DESC) WHERE deleted_at IS NULL` — the dashboard list query.
- `(destination_url)` using `gin_trgm_ops` — admin search by destination (FR-030).

**State**

```
active ──ban──→ banned ──unban──→ active
  │                 │
  └──delete──→ deleted ←──delete──┘
```

`deleted` is terminal in MVP; there is no undelete. A deleted link keeps its `code` forever, which
is how FR-029's 30-day quarantine is satisfied without a quarantine mechanism (D12).

**Redirect resolution order** — evaluated in this order, first match wins:
1. `deleted_at` present → not-found page
2. `banned_at` present, or owning account's `banned_at` present → safety warning page
3. otherwise → 302 to `destination_url`

**Invariants**
- `code` is never updated. Enforced by an `attr_readonly`-style guard in the model *and* asserted by
  a test; there is no database trigger, as no legitimate code path attempts it.
- Two links may share `destination_url` freely. There is no unique constraint on it, deliberately
  (FR-011) — deduplicating destinations would merge two customers' statistics.

---

### clicks

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `link_id` | uuid | NOT NULL, FK → links | |
| `occurred_at` | timestamptz | NOT NULL | captured in the middleware, not at insert time |

**Indexes**: `(link_id, occurred_at DESC)`.

**Rules**
- No IP address column exists. Not nullable-and-unused — absent, so it cannot be populated by a
  later careless commit (Principle V, FR-024).
- Rows are written only by the batch flush job, never by a web request (D4, Principle I).
- Retained 7 days, then deleted by a daily job. `clicks_count` on `links` survives the purge, so a
  creator's total is not affected by retention.

**Deferred, by design**: `country`, `device_type`, `browser`, `referrer`, `utm_*`, `is_bot`, and
`visitor_fingerprint` are all out of MVP scope. The table is shaped so they are additive columns.
`is_bot` in particular must be addable without discarding history — which it is, since existing rows
default to "not classified" rather than to "human".

**Deferred aggregation**: `click_hourly_rollups (link_id, hour, human_count, bot_count)` is the
stated path to a year of history without a billion rows. Not built in MVP; the 7-day retention cap
exists so its absence cannot become an unbounded-growth problem.

---

### blocked_domains

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `domain` | citext | NOT NULL, UNIQUE | registrable domain; matching also covers subdomains |
| `reason` | text | NULL | |
| `created_by_id` | uuid | FK → accounts | which admin added it |
| `created_at` | timestamptz | NOT NULL | |

Checked at creation and at destination edit (FR-007). Existing links are not retroactively banned by
an addition here — that is a separate deliberate admin action.

---

### reports

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | |
| `link_id` | uuid | NOT NULL, FK → links | |
| `reason` | text | NULL | free text from the warning page |
| `status` | text | NOT NULL, DEFAULT `'pending'`, CHECK IN (`pending`, `actioned`, `dismissed`) | |
| `reviewed_by_id` | uuid | NULL, FK → accounts | |
| `reviewed_at` | timestamptz | NULL | |
| `created_at` | timestamptz | NOT NULL | |

**Indexes**: `(status, created_at)` for the queue; `(link_id)`.

Submitted by anonymous visitors, so the endpoint is rate-limited by IP (transiently, in Redis) and
stores no reporter identity.

---

## Redis

None of this is a source of truth. Total loss degrades throughput and statistics freshness and
nothing else (Principle I, SC-008).

| Key | Type | TTL | Purpose |
|---|---|---|---|
| `link:<code>` | string | 24h, refreshed on read via `GETEX` (D6) | packed destination + state, or the `__404__` sentinel (D7) |
| `lock:<code>` | string | 5s | single-flight rebuild on miss (D5) |
| `clicks:buffer` | list | none | click events awaiting flush (D4) |
| `account:<id>:codes` | set | 24h | codes this account has cached, so an account ban can invalidate them without a `SCAN` (D14) |
| `ratelimit:create:<account_id>` | string | 1h | link-creation throttle |
| `ratelimit:report:<ip_hash>` | string | 1h | report-abuse throttle; the IP is hashed, never stored raw |
| `ratelimit:auth:<ip_hash>` | string | 1h | registration and sign-in throttle per origin (FR-036); the IP is hashed, never stored raw |
| `ratelimit:signin:<email_hash>` | string | 1h | sign-in throttle per target account (FR-036); the address is hashed |

**Cached value**: a compact encoding of `destination_url`, `banned` and `deleted` flags, and the
owning account's banned flag — everything the redirect decision needs. Account bans must therefore
invalidate every cached link of that account, not just the account row; `account:<id>:codes` is what
makes that possible in O(links cached) rather than O(keyspace). See research.md D14.

**Configuration, from the first deployment** (Principle IV): `maxmemory` set explicitly,
`maxmemory-policy allkeys-lru`. Sidekiq uses a separate database index so a cache eviction storm
cannot touch the job queue.

**Cold-start behaviour**: an empty Redis is correct, merely slower. Every miss falls through to
Postgres and repopulates. No warm-up job exists and none is needed.
