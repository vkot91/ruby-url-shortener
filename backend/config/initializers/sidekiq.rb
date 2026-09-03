# Sidekiq gets its own Redis database index, so that a queued job and a cached
# link cannot collide on a key name and so that emptying one does not empty the
# other (Principle IV, research.md D9).
#
# What the split does *not* do is protect the queue from eviction. `maxmemory`
# and `maxmemory-policy` are server-wide settings, so the `allkeys-lru` that
# docker-compose.yml configures applies to db1 exactly as it does to db0: under
# memory pressure Redis may discard a queued job, turning what reads like a
# cache eviction into lost work. The only real isolation is a second instance,
# which the reference environment does not need — the working set is ~0.5% of
# the 512mb budget — and which production should have.
SIDEKIQ_REDIS_URL = ENV.fetch("SIDEKIQ_REDIS_URL")

Sidekiq.configure_server do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }
end

Sidekiq.configure_client do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }
end
