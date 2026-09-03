#!/usr/bin/env bash
#
# Runs the click-flush worker in the reference configuration (T059).
#
#   load/worker.sh
#
# The cached run needs this and the naive run does not, which is the one place
# Principle II's "the two runs differ only in the code under test" needs a word
# of explanation: the work has not been added, it has been moved. 3A wrote the
# click row and the counter inside the request; 3C writes the same rows from
# here, in batches, on the same host, competing for the same CPU. Leaving the
# worker out would let the cached run report a throughput it only reaches by not
# doing the writing at all.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

exec bundle exec sidekiq -C config/sidekiq.yml
