# frozen_string_literal: true

# Where Rails' `rate_limit` keeps its counters.
#
# It defaults to `Rails.cache`, and neither of this application's `Rails.cache`
# settings is the right home for them. In test that is `:null_store`, which
# counts nowhere — a limiter backed by it accepts every request and its specs
# pass by never limiting anything. In production the Rails 8 default is
# Postgres-backed, which would put write load proportional to sign-in and
# link-creation volume onto the store this whole architecture exists to keep
# load off (D9's reasoning, applied to counters rather than to jobs).
#
# The counters are expendable by design — data-model.md lists every
# `ratelimit:*` key under Redis and notes that losing them costs a window of
# throttling and nothing else — so they belong in Redis next to the read cache.
#
# The test environment uses an in-process store rather than Redis. The thing
# under test is the application's limits and its refusal bodies, not
# `ActiveSupport::Cache`'s Redis adapter, and an in-process store makes those
# specs deterministic without a network round trip per example.
RATE_LIMIT_STORE =
  if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV.fetch("REDIS_URL"),
      namespace: "ratelimit",
      # Fail open. A Redis outage must not lock everybody out of sign-in, and
      # per Principle I's ordering an unavailable expendable store degrades the
      # protection it provides rather than the service it protects.
      error_handler: ->(method:, returning:, exception:) {
        Rails.logger.warn(JSON.generate(event: "rate_limit_store_error", method: method, error: exception.class.name))
      }
    )
  end
