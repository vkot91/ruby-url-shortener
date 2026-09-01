#!/usr/bin/env bash
#
# The reference environment, in one place (T042). Sourced by load/seed.sh and
# load/serve.sh so the corpus is written by exactly the configuration that
# later serves it, and so the 3B and 3C runs cannot drift apart in a log level
# or a thread count nobody noticed.
#
# Why production mode rather than development: development reloads code, checks
# file mtimes on every request, and carries the debug-exceptions and
# server-timing middleware. A baseline measured through those describes Rails'
# development conveniences, and the 3C run would then take credit for removing
# them.
#
# `config.force_ssl` is true in production and needs no working around:
# `config.assume_ssl` is true as well, so ActionDispatch::AssumeSSL marks every
# request secure before ActionDispatch::SSL looks at it. Nothing in the
# application is modified to run this.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../backend"

# dotenv-rails loads .env in development and test only, so the reference
# environment exports it by hand — the same names, out of the same file the
# rest of the stack uses.
set -a
# shellcheck disable=SC1091
source .env
set +a

export RAILS_ENV=production

# Not a real secret and not stored: this process serves redirects out of a
# throwaway database and signs nothing anybody keeps.
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-load-test-not-a-secret}"

# The corpus lives in its own database rather than in shortener_development, so
# a run measures the 10 000 seeded links and nothing a developer left behind —
# and so a baseline's millions of click rows land somewhere disposable.
export DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/shortener_load"

# One line per request at several thousand requests a second is disk I/O
# attributed to the read path. Silenced for both runs equally; that the redirect
# logs one line is asserted in the specs, not here.
export RAILS_LOG_LEVEL=error
