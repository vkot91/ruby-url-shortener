#!/usr/bin/env bash
#
# Prints Postgres' committed-transaction count for the load database.
#
# Both SC-007 verifications — enumeration (T060) and the stampede (T061) — are
# claims about what the *database* was asked to do, and neither is observable
# from the client: a request answered out of Redis and a request answered out of
# Postgres look identical from k6 except in latency, and latency is noise at
# these numbers. So the assertion is made against Postgres' own counter, read
# either side of the run.
#
# `xact_commit` rather than a statement count: pg_stat_statements is not
# installed, and every statement the application issues runs in its own implicit
# transaction, so a transaction is a query here. The counter also moves for
# anything else touching the database during the window, which is why the
# scripts that use this print the raw delta rather than asserting on an exact
# number.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

docker compose exec -T postgres \
  psql -U "${POSTGRES_USER}" -d shortener_load -tAc \
  "SELECT xact_commit FROM pg_stat_database WHERE datname = 'shortener_load'"
