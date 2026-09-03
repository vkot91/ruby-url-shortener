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

if Rails.env.development?
  require "sidekiq/web"

  # Sidekiq's dashboard is mounted at /sidekiq in development (config/routes.rb).
  # It guards its own POSTs — retry, kill, clear a queue — with a CSRF token, and
  # that token lives in a Rack session this application does not have:
  # `config.api_only` leaves session middleware out of the stack entirely, which
  # config/application.rb notes and RedirectMiddleware's position depends on.
  #
  # So the session is given to the dashboard's own Rack app rather than to the
  # application. Nothing else in the stack acquires a session, and the cookie is
  # scoped to a dashboard that exists in development only.
  #
  # Here rather than in config/routes.rb because routes are reloaded on every
  # edit in development and `use` appends — the middleware would stack up one
  # copy per reload.
  # Action Dispatch's own pair rather than `Rack::Session::Cookie`: the mount
  # sits inside the router, so the request already carries the application's key
  # generator and the cookie is signed with `secret_key_base` without a secret
  # being named here.
  Sidekiq::Web.use ActionDispatch::Cookies
  Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: "_shortener_sidekiq_session"
end
