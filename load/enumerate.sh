#!/usr/bin/env bash
#
# T060, SC-007. Drives absent codes at the service and reports what Postgres saw
# while it happened.
#
#   load/serve.sh true      # separate shell
#   load/enumerate.sh
#
# The number to look at is the last line. Enumeration of a pool of 500 absent
# codes at 2 000 requests a second for 30 seconds is 60 000 requests; the naive
# path answers every one of them with a Postgres query, and the cached path is
# expected to answer all but the first sighting of each code out of Redis. So
# the delta should be in the hundreds, not the tens of thousands, and it should
# not grow with the duration of the run — that is what "flat Postgres load"
# means.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RESULT="${RESULT:-load/results/enumerate.json}"

before=$(./load/pg_transactions.sh)

k6 run -e RESULT="${RESULT}" load/enumerate.js

after=$(./load/pg_transactions.sh)

echo "Postgres transactions during the run: $((after - before))"
