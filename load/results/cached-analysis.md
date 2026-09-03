# The cached read path, measured against the baseline

**Run**: 2026-09-01 · `REDIRECT_CACHE_ENABLED=true` · results in [`cached.json`](./cached.json)
**Environment**: [`load/README.md`](../README.md) — identical to the baseline in every respect
except the flag and the presence of the click-flush worker, which is where the writes the naive
path did inline now happen.

This is task T059 and the exit condition for Phase 3C. The baseline it is measured against is
[`naive-analysis.md`](./naive-analysis.md); the script, the corpus, the seed, the host and the
Zipf exponent are the same, and `redirect.js` was not edited between the two runs.

## The number

Both columns are one Puma worker, `RAILS_MAX_THREADS=5`, which is the reference environment.

| Offered req/s | Naive served/s | Cached served/s | Naive p99 | Cached p99 |
|---:|---:|---:|---:|---:|
| 500 | 500 | 500 | 12 ms | 10 ms |
| 1 000 | 1 000 | 1 000 | 59 ms | 5 ms |
| 2 000 | 1 090 | 2 000 | 3 746 ms | 22 ms |
| 4 000 | 1 107 | 3 136 | 4 159 ms | 986 ms |
| 6 000 | 1 122 | 3 054 | 4 482 ms | 1 544 ms |
| 8 000 | 1 129 | 3 359 | 4 190 ms | 1 346 ms |

**1 130 → ~3 350 redirects per second on one worker: 3.0×.** The rate at which SC-001's 50 ms p99
still holds moves further than the throughput does — from 500/s to 2 000/s, **4×** — because the
cached path is not merely doing the same work faster, it is doing a fixed small amount of work per
request instead of an amount that grows with how busy the process is.

The baseline document warned that its own knee moved between repetitions and asked that a single
measurement near it not be read as precise. The cached run was therefore taken twice, cold cache
both times: 3 127 / 3 032 / 3 321 the first time and 3 136 / 3 054 / 3 359 the second, at the three
saturated steps. **Within 1%** — the cached path's ceiling is flat and repeatable in a way the
naive path's knee was not, which is itself a consequence of the work per request no longer varying.

Correctness held on both sides, at every step: 391 506 redirects checked in the committed run,
**zero** wrong destinations, `Cache-Control: no-store` on 100% of responses, **zero** `Set-Cookie`
headers, zero errors. That is Principle II's requirement that the comparison be about throughput
alone.

## SC-002: the hit ratio

Measured directly, with Redis' own counters reset immediately before the run and the cache empty:

```
keyspace_hits    381 715
keyspace_misses    9 986        →  97.45%
```

**97.45%, against a bar of 95%** — and the misses are not a defect but the corpus: 9 986 of the
10 000 links were reached at least once by the Zipf draw, and a cold cache has to fetch each of
them exactly once. Every subsequent request for any of them was served from Redis. Postgres saw
11 373 committed transactions across the whole run against 391 506 redirects; the naive path, at
four statements per redirect, would have issued roughly 1.5 million.

## Against the success criteria

| | Naive | Cached, 1 worker | Cached, 4 workers |
|---|---|---|---|
| **SC-001** p99 ≤ 50 ms | to 500/s | to 2 000/s | to 6 000/s |
| **SC-004** ≥ 5 000 req/s | ✗ 1 130 | ✗ ~3 350 | ✓ 6 000 sustained, ~7 700 ceiling |
| **SC-002** cache hit ratio ≥ 95% | n/a | ✓ 97.45% | ✓ |
| **SC-005** ≥ 99.9%, no wrong destination | ✓ | ✓ | ✓ |
| **SC-007** absent codes / stampede | ✗ | ✓ | ✓ |
| **SC-008** Redis loss degrades statistics only | n/a | ✓ | ✓ |

The single-worker cached path does **not** meet SC-004, and the fourth column is why that is a
statement about process count rather than about the read path — see the addendum below.

## Where the clicks went

The redirect no longer writes to Postgres at all. It pushes `<link_id>:<epoch ms>` onto
`clicks:buffer` after the response triple is built, and `Clicks::FlushJob` drains the list every
five seconds in batches of a thousand (D4, FR-020, FR-021).

Measured at the end of the first cached run, whose 389 413 k6 iterations were the only traffic the
database had seen since the corpus was seeded, plus one smoke-test request by hand:

```
LLEN clicks:buffer                                    0
SELECT count(*) FROM clicks                     389 414
SELECT sum(clicks_count) FROM links             389 414
```

**No click was lost, and the counters agree with the rows exactly** — under 3 300 redirects a
second, with the flush job competing for the same CPU as the process serving them. The buffer
drained to empty rather than growing, which is the property that decides whether this design
survives a sustained peak or merely a burst.

The same two totals were checked again after every run in this document — five k6 runs, the
stampede, the enumeration, and the naive runs whose clicks are written by the other path
entirely — and they have never disagreed:

```
SELECT count(*) FROM clicks                   1 786 574
SELECT sum(clicks_count) FROM links           1 786 574
```

That is the thing worth asserting about a counter maintained by a batch job: not that it is fast,
but that it is exact.

## SC-007, verified rather than argued

Both checks report what *Postgres* saw, because that is where the claim lives: from outside, a
request answered from Redis and one answered from Postgres are the same response.
`load/pg_transactions.sh` reads `pg_stat_database.xact_commit` either side of the run.

### Enumeration (T060, `load/enumerate.sh`)

60 001 requests at 2 000/s against a pool of 500 absent codes:

```
404 rate    100.000%
p50 / p99   0.4 ms / 43.7 ms
Postgres transactions during the run: 504
```

**One query per code, not one per request.** 500 of those 504 are the first sighting of each code;
the remainder are the flush job's own commits during the window. The naive path would have issued
60 001. This is what "flat Postgres load under enumeration" means, and it is the difference
between a code-space walk being ordinary traffic and being an outage.

### Stampede (T061, `load/stampede.sh`)

The corpus's rank-0 link — the one the Zipf draw makes hottest — warmed, then its cache entry
deleted, then 500 concurrent requests in one shot:

```
requests    500
correct     100.000%
p50 / p99   71.0 ms / 113.8 ms
Postgres transactions during the run: 3
```

**3, not 500.** One rebuild by the winner of `SET lock:<code> NX EX 5`, and every other request
served the value it published (D5). The latency is higher than a steady-state hit and should be:
losers wait ~10 ms at a time for the winner rather than stampeding the database. Note also that
all 500 got the correct destination — a single-flight that answered some of them with a miss would
have moved the problem rather than solved it.

Deleting the key is exactly what an edit does (T058), so this run doubles as the concurrency test
for invalidation.

## The new bottleneck

The baseline named the old one: work per request in a single GVL-bound Ruby process, of which
~62% of the SQL was the click write and a quarter was an N+1 on the owning account. All of that is
gone from the request — one `GETEX`, no controller, no session, no ActiveRecord object, no
Postgres.

What is left is the process itself. Sampled with `top` across the saturated steps of the
single-worker run:

| | At the saturated steps |
|---|---:|
| Puma process | **84–90% of one core** |
| Sidekiq (the flush job) | 8% |
| k6, on the same host | 130–140% |
| Docker VM (Redis, and Postgres doing almost nothing) | 170–180% |
| Postgres container | 0.1% |

The shape of the constraint is unchanged from 3B even though its content is entirely different:
one Ruby process, one core, and a machine with eleven others it cannot use. The database that was
the *reason* for the whole design is now measurably idle underneath it. Note also that k6 is using
more CPU than the thing it measures, which is the co-residency cost `load/README.md` warns about
and a reason to treat ~3 350/s as a floor rather than a ceiling.

That distinction is testable, and testing it is the point of the addendum: if the ceiling is the
process, adding processes moves it, and if it is the architecture, adding processes does not.

## Addendum: four workers

**Not the reference environment.** `WEB_CONCURRENCY=4`, everything else identical, results in
[`cached-4-workers.json`](./cached-4-workers.json) and
[`naive-4-workers.json`](./naive-4-workers.json). It is reported separately for that reason, and
the headline comparison above stays at one worker on both sides.

| Offered req/s | Naive, 4 workers | Cached, 4 workers |
|---:|---:|---:|
| 500 | 500 (p99 14 ms) | 500 (p99 6 ms) |
| 1 000 | 1 000 (p99 16 ms) | 1 000 (p99 3 ms) |
| 2 000 | 2 000 (p99 152 ms) | 2 000 (p99 3 ms) |
| 4 000 | 1 839 (p99 2 021 ms) | 4 000 (p99 13 ms) |
| 6 000 | 2 024 (p99 2 253 ms) | 6 000 (p99 25 ms) |
| 8 000 | 2 057 (p99 2 613 ms) | 7 699 (p99 163 ms) |

The naive column is the one that settles the question. **Four times the processes bought the naive
path 1.8× the throughput — 1 130 to 2 057 — and left it below the single-worker cached path's
3 300.** It does not scale with process count because the work it does per request is work
Postgres does, and the workers share one Postgres: sampled during its saturated steps, the four
Puma workers sat at ~48% of a core each while the Docker VM hosting Postgres took **308%**, three
whole cores. The cached path's saturated steps put no worker above ~40% and Postgres at 0.1%.

So the two builds do not merely differ in speed, they differ in what they run out of, and only one
of them can be given more of it.

**The cached path meets SC-004 with four workers: 6 000 redirects a second at a p99 of 25 ms**,
and does not saturate until somewhere near 7 700 — measured with k6 itself taking a whole core on
the same twelve-core box, so the ceiling is at least partly the measuring instrument.

At those steps no Puma worker was above ~40% of a core, which is the answer to the question the
addendum was run to ask: with the read path this small, four processes are not what is limiting the
result — k6 and the container VM are closer to being it. The single-worker ceiling was the process,
exactly as the baseline predicted it would be if the read path stopped allocating.

`config/puma.rb` gained a `workers` line for this. It defaults to zero — single-process, the
reference environment — so no committed run moves because the knob exists.

## What this does not claim

- **Absolute numbers are host-specific and generator-limited.** k6, Puma, Postgres and Redis share
  twelve cores, and at the top steps k6 alone uses one of them. The transferable results are the
  ratio at fixed configuration (2.9×) and the shape of what changed.
- **The corpus is 10 000 links.** A working set that does not fit in Redis behaves differently;
  `maxmemory 512mb` with `allkeys-lru` is configured for that case (Principle IV) but this run does
  not exercise it.
- **The Zipf draw is a model, not a trace.** `s = 1.07` is the usual fit for web popularity, and
  both runs use it, but a real link's traffic is burstier than any stationary distribution.
- **Nothing here measures a cold Redis under load.** Cold-start behaviour is correct by
  construction — every miss falls through and repopulates — and the stampede run is the closest
  thing to a stress test of it.
