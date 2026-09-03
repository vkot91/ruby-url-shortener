# Puma runs `RAILS_MAX_THREADS` threads per process and the redirect middleware
# takes a connection for the duration of a single GETEX, so the pool is sized to
# the thread count: any smaller and threads queue on Redis instead of Postgres,
# which is the bottleneck this architecture exists to remove.
REDIS_POOL_SIZE = Integer(ENV.fetch("RAILS_MAX_THREADS"))

# The database index the suite is allowed to destroy.
#
# From Phase 3C the specs assert on real Redis state — a TTL that `GETEX`
# refreshed, a sentinel that expired, a buffer that the flush job drained — and
# none of that survives being stubbed. So they run against the same server as
# development, in a database index of their own, and spec/support/redis.rb
# empties it between examples. Without the split, running the suite would
# silently flush the developer's link cache.
#
# Derived rather than configured: `.env` names one Redis URL, and a second name
# that must be the first one with a different number on the end is a way for the
# two to drift apart on somebody's machine.
TEST_REDIS_DATABASE = 15

REDIS_URL =
  if Rails.env.test?
    URI(ENV.fetch("REDIS_URL")).tap { |url| url.path = "/#{TEST_REDIS_DATABASE}" }.to_s
  else
    ENV.fetch("REDIS_URL")
  end

REDIS = ConnectionPool.new(size: REDIS_POOL_SIZE, timeout: 1) do
  Redis.new(url: REDIS_URL, timeout: 1)
end

# What "the cache is not answering" looks like from Ruby, in one list because
# more than one caller has to degrade around it.
#
# The pool's timeout is in it because that is the failure a saturated Redis
# actually produces — every connection busy rather than the server unreachable —
# and it is not a `Redis::BaseError`. Rescuing only the latter would turn a slow
# cache into a 500 on the one path that must never have one.
REDIS_UNAVAILABLE_ERRORS = [ Redis::BaseError, ConnectionPool::TimeoutError ].freeze
