# Baseline: the naive read path

**Run**: 2026-09-01 · `REDIRECT_CACHE_ENABLED=false` · results in [`naive.json`](./naive.json)
**Environment**: [`load/README.md`](../README.md) — Apple M3 Pro (12 cores, 36 GB), everything
co-resident, Rails 8 in production mode, one Puma worker, `RAILS_MAX_THREADS=5`, corpus of
10 000 links at seed `20260901`, Zipf `s = 1.07`.

This is task T043/T044 and the exit condition for Phase 3B: a committed number and a named
bottleneck. It measures the implementation the constitution's Principle I waiver was granted
for — one Postgres lookup per redirect and a synchronous click write — so that Phase 3C's
improvement is a measured delta rather than an assertion.

## The number

| Offered req/s | Served req/s | p50 | p99 | Errors | Unserved |
|---:|---:|---:|---:|---:|---:|
| 500 | 500 | 3 ms | 12 ms | 0.00% | 0 |
| 1 000 | 1 000 | 4 ms | 59 ms | 0.00% | 0 |
| 2 000 | 1 090 | 2 000 ms | 3 746 ms | 0.00% | 27 308 |
| 4 000 | 1 107 | 3 916 ms | 4 159 ms | 0.00% | 86 790 |
| 6 000 | 1 122 | 3 937 ms | 4 482 ms | 0.00% | 146 346 |
| 8 000 | 1 129 | 3 952 ms | 4 190 ms | 0.00% | 206 142 |

**The naive path sustains roughly 1 130 redirects per second.** Above that, the offered rate and
the served rate part company: the service goes on answering at ~1 100/s no matter how much more is
asked of it, and the surplus becomes queue delay.

`Unserved` is derived — offered minus served, over the step's 30 seconds — because k6's
`dropped_iterations` carries no scenario tag. It is worth stating that it agrees with the untagged
figure k6 does report: the derived columns total 466 586, and k6 counted 466 591 iterations it
could not start because every virtual user it was allowed was still waiting on a response. Two
independent routes to the same number.

Against the success criteria:

- **SC-004 (≥5 000 req/s)** — missed by a factor of **4.4**.
- **SC-001 (p99 ≤ 50 ms)** — held at 500 req/s (12 ms). Broken by 1 000 req/s (59 ms). Beyond
  that, p99 is roughly four seconds, which is less a latency figure than the depth of the queue.

- **SC-005 (≥99.9% availability, zero incorrect destinations)** — **passed, at every step**.
  178 416 requests, zero errors, zero wrong destinations, `Cache-Control: no-store` on 100% of
  responses, and no `Set-Cookie` anywhere.

The knee between 1 000 and 2 000 req/s is sharp, and it is the one part of this run that moves
between repetitions: an earlier run of the identical script put the 1 000 req/s step at p50 87 ms
and p99 149 ms rather than 4 ms and 59 ms. Either way that step fails SC-001 and the step above it
collapses, so the conclusion is unchanged — but a 3C comparison should not read a single
measurement near the knee as precise.

That last criterion matters for reading the rest of this document. The naive build is not broken or
flaky. It is *correct and slow*, which is exactly what a baseline should be: the 3C comparison is
then about throughput alone, with correctness held fixed on both sides.

## The bottleneck

plan.md named three candidates in advance — connection pool exhaustion, the per-click insert, or
query latency. Measured, it is the second, sitting underneath a harder ceiling that is none of
the three.

### It is not connection pool exhaustion

Ruled out, not assumed. Across the whole run:

- zero `ActiveRecord::ConnectionTimeoutError`, and zero errors of any kind in the server log;
- 6 Postgres connections in `pg_stat_activity` against a `max_connections` of 100.

The pool is 5 because the thread count is 5, so a thread can never queue for a connection — it
*is* the connection. The pool cannot be the constraint when it is sized to the only thing that
can ask for one.

### It is not query latency

Every statement on the redirect path is a primary-key or unique-index lookup, and warm they cost
tenths of a millisecond:

```
statements per redirect: 4
  Link Load        SELECT "links".*    WHERE "code" = $1 LIMIT 1
  Account Load     SELECT "accounts".* WHERE "id"   = $1 LIMIT 1
  Click Insert     INSERT INTO "clicks" ("link_id","occurred_at") VALUES (…)
  Link Update All  UPDATE "links" SET "clicks_count" = COALESCE("clicks_count",0) + 1 WHERE "id" = $1
```

Postgres was never in difficulty. At the saturated steps it ran at **28% of one core** while the
box had twelve. The four-second p99 is queue delay in front of the application, not time spent in
the database.

### It is the work done per request, in a process that has one core to do it in

The measurement that names it, sampled at the saturated steps of a preceding, identically
configured run of this script (`top` on the Puma process, `docker stats` on the containers):

| | At the saturated steps |
|---|---|
| Puma process CPU | **107%** — one core, pinned |
| Postgres container CPU | 28% |
| Redis container CPU | 0.2% — unused by the naive path |
| Machine | 12 cores |

One Puma worker is one Ruby process, and a Ruby process executes Ruby on one core at a time.
Threads help only while they are blocked on I/O; they cannot add a second core's worth of
interpreter. So the ceiling is *work per request*, and the only way through it is to do less of
it — which is precisely what Phase 3C does, and why 3C is a rewrite of the path rather than a
tuning pass.

Decomposing that work, single-threaded and uncontended (300 requests through the full Rack stack,
with the SQL instrumented):

| | per request | share of SQL |
|---|---:|---:|
| Click Insert | 1.45 ms | 33% |
| Link Update All (counter) | 1.33 ms | 30% |
| Link Load | 0.91 ms | 20% |
| Account Load | 0.76 ms | 17% |
| **SQL total** | **4.45 ms** | |
| Ruby / Rack remainder | 3.29 ms | |

Read as proportions rather than as absolute latencies — this probe measures in-process with an
instrumentation subscriber attached, and reports a higher figure than the 3 ms the server actually
served at 500 req/s. What it establishes is the *shape* of the cost, and the shape has two
removable pieces:

1. **The synchronous click write is the largest single term.** Two of the four statements exist to
   record a statistic, and together they are ~62% of the SQL on the path. Nothing about a visitor
   reaching their destination requires them to happen first, or at all, before the response.
   FR-021 and D4 move them to a Redis buffer drained in batches, and this table is the reason that
   is worth doing.

2. **`Account Load` is an N+1 on the hot path.** `RedirectsController#show` reads
   `link.account.banned_at`, which fetches the entire owning account on every redirect to look at
   one timestamp. A quarter of the statements, for one boolean. This is not a defect in 3A — the
   resolution order in data-model.md has to be honoured from the start — but it is the concrete
   reason T047's cached value is specified as *packed*, carrying the banned, deleted and
   account-banned flags alongside the destination. One `GETEX` answers what two SELECTs answer
   here.

## What 3C has to beat, and how the comparison should be read

**1 130 redirects/second, p99 within 50 ms only up to 500/s.**

`redirect.js` is reused unchanged for the cached run, against the same corpus, on the same host,
with only `REDIRECT_CACHE_ENABLED` flipped. Two caveats belong with the comparison when it is
made:

- **One Puma worker, both times.** A production deployment would run several and scale roughly
  linearly, so 1 100/s is a *per-worker* figure, not a claim about what a deployment of this code
  could serve. Since both runs use one worker, the ratio between them is the transferable result
  and the absolute numbers are not.
- **k6 shares the host.** It contends for CPU with the thing it measures. With Puma pinned to one
  core of twelve there was headroom here, but a cached run fast enough to use several cores may
  start to feel it, and should say so if it does.

The prediction the next phase is measured against: removing two writes and two reads from the
request path, and answering ahead of the router without instantiating a controller, a session, or
an ActiveRecord object, should move the constraint off the application process. If the cached run
does not clear 5 000/s, the thing to check first is whether the read path is still allocating —
because after this measurement, the read path's cost is the only thing standing between the two
numbers.
