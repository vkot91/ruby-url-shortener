#!/usr/bin/env bash
#
# Boots the backend in the reference configuration for a load run (T042).
#
#   load/serve.sh false     # naive path — the Phase 3B baseline
#   load/serve.sh true      # cached path — Phase 3C
#
# The flag is the only difference between the two runs, which is the whole of
# Principle II. It is read once at boot (config/application.rb), so flipping it
# means restarting this script rather than editing anything.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

export REDIRECT_CACHE_ENABLED="${1:-false}"

# Left at whatever backend/.env says — 5 at the time of writing — deliberately.
# That file's comment is explicit that the small pool is there so the naive
# path's queueing shows up in the baseline rather than being tuned away, and
# raising it here would be tuning it away in the one place it matters.
echo "RAILS_MAX_THREADS=${RAILS_MAX_THREADS}  REDIRECT_CACHE_ENABLED=${REDIRECT_CACHE_ENABLED}"

exec bin/rails s
