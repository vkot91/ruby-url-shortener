# Sidekiq gets its own Redis database index. db0 runs `allkeys-lru` for the link
# cache and click buffer; evicting a queued job under memory pressure would turn
# a cache eviction into lost work (Principle IV, research.md D9).
SIDEKIQ_REDIS_URL = ENV.fetch("SIDEKIQ_REDIS_URL")

Sidekiq.configure_server do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }
end

Sidekiq.configure_client do |config|
  config.redis = { url: SIDEKIQ_REDIS_URL }
end
