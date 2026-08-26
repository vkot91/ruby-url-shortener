# Contract: Public Redirect Surface

**Host**: the short domain. Served by `RedirectMiddleware` ahead of the Rails router (D1).

This surface is anonymous, unauthenticated, and cookieless. It is specified separately from the JSON
API because it is not JSON, and because its latency budget makes its contract unusually strict.

## `GET /:code`

`code` is 3–32 characters from `[A-Za-z0-9]`. Anything else falls through to the Rails router.

| Condition | Status | Body | Headers |
|---|---|---|---|
| Active link | `302 Found` | empty | `Location: <destination>`, `Cache-Control: no-store` |
| Unknown or deleted code | `404 Not Found` | not-found HTML | `Cache-Control: no-store` |
| Link banned, or owning account banned | `403 Forbidden` | safety warning HTML with report control | `Cache-Control: no-store` |

**Guarantees**

- No `Set-Cookie` header is emitted on any of the three outcomes (FR-015, Principle V).
- `Cache-Control: no-store` on the 302 is mandatory, not advisory — a cached redirect breaks
  destination editing (D8, FR-016).
- At most one Redis round trip (`GETEX`) on a cache hit. No Postgres access, no session, no
  ActiveRecord object (Principle I).
- The click is recorded by `LPUSH` after the response triple is constructed. A Redis failure here
  MUST NOT alter the response (FR-021, SC-008 — statistics degrade, redirects do not).
- The response is never rate-limited or gated on the owning account's plan (FR-019).

**Prohibited on this path** — these are the gate conditions for review:
no synchronous Postgres query on a cache hit; no `Set-Cookie`; no analytics enrichment
(geolocation, user-agent parsing); no per-request logging beyond one structured line.

## `POST /:code/report`

Anonymous, from the warning page. Body: `{ "reason": "<string, optional, max 500>" }`.
Returns `204 No Content` on success, `429 Too Many Requests` when the per-IP hourly limit is hit.
The reporter's IP is hashed for throttling only and is never persisted (FR-033).

## Reserved paths

`/api/*`, `/up`, `/admin`, `/login`, `/settings`, and the static asset prefix are matched by the
router before the middleware's code pattern applies, and are rejected as codes at creation (FR-012).
