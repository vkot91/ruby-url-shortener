#!/usr/bin/env bash
#
# T061, SC-007, D5. Deletes the hottest link's cache entry and drives 500
# concurrent requests at it, then reports what Postgres saw.
#
#   load/serve.sh true      # separate shell
#   load/stampede.sh
#
# The number to look at is the last line. Without single-flight it is ~500 — one
# query per request in flight, which is the stampede. With it, it is a small
# handful: the winner of the lock, plus any loser whose wait ran out before the
# winner published.
#
# The code is rank 0 of the corpus, which under the Zipf draw is the link that
# takes the largest share of the traffic — the "viral link" the spec's edge case
# is about, rather than an arbitrary one.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RESULT="${RESULT:-load/results/stampede.json}"

CODE=$(ruby -rjson -e 'puts JSON.parse(File.read("load/corpus.json"))["codes"][0]')
EXPECTED=$(ruby -rjson -e 'puts JSON.parse(File.read("load/corpus.json"))["destination_pattern"].sub("%d", "0")')

# Source the environment only now: env.sh cds into backend/, and the two ruby
# invocations above read a path relative to the repository root.
source ./load/env.sh

# Warm the entry first, so the run measures a *hot key expiring* rather than a
# code nobody had asked for yet. Without this the deletion below is a no-op and
# the 500 requests are 500 first sightings, which is a different event.
curl -s -o /dev/null "http://localhost:3001/${CODE}"

# The expiry, made to happen on demand. Deleting the key is what a 24-hour TTL
# reaching its end looks like from the application's side, and it is also
# exactly what an edit does (T058) — so this run doubles as the concurrency test
# for invalidation.
docker compose exec -T redis redis-cli -n 0 DEL "link:${CODE}" > /dev/null
docker compose exec -T redis redis-cli -n 0 DEL "lock:${CODE}" > /dev/null

cd ..

before=$(./load/pg_transactions.sh)

k6 run -e CODE="${CODE}" -e EXPECTED="${EXPECTED}" -e RESULT="${RESULT}" load/stampede.js

after=$(./load/pg_transactions.sh)

echo "Postgres transactions during the run: $((after - before))"
