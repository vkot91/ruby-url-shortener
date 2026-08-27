# Puma runs `RAILS_MAX_THREADS` threads per process and the redirect middleware
# takes a connection for the duration of a single GETEX, so the pool is sized to
# the thread count: any smaller and threads queue on Redis instead of Postgres,
# which is the bottleneck this architecture exists to remove.
REDIS_POOL_SIZE = Integer(ENV.fetch("RAILS_MAX_THREADS"))

REDIS = ConnectionPool.new(size: REDIS_POOL_SIZE, timeout: 1) do
  Redis.new(url: ENV.fetch("REDIS_URL"), timeout: 1)
end
