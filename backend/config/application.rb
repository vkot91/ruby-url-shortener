require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Sidekiq, not the default async adapter. `perform_later` under the async
    # adapter runs the job in a thread pool inside Puma and drops whatever is
    # queued when the process restarts — so the Sidekiq process would sit idle
    # while the work it exists for happened somewhere less durable. There are no
    # jobs yet; the click-flush job in Phase 3C (T055) is the first, and this is
    # the sort of default that is discovered by a job silently not running.
    #
    # A spec that enqueues will need Sidekiq::Testing to keep the assertion off
    # a live Redis. Nothing enqueues today, so that arrives with the first job
    # rather than as unused setup now.
    config.active_job.queue_adapter = :sidekiq

    # Primary keys are UUIDs, so a generated migration has to default to one:
    # a table created with a bigint key would be found by the foreign key that
    # cannot point at it, which is a confusing way to learn about a convention.
    config.generators do |generate|
      generate.orm :active_record, primary_key_type: :uuid
    end

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # No cookie middleware, deliberately. Authentication is bearer-token only
    # (research.md D10), so nothing in this application can set a cookie even by
    # accident — which turns the redirect's "no Set-Cookie" guarantee (FR-015,
    # Principle V) from an assertion into a structural fact.

    # The short domain the codes are served from. Used to render short_url and,
    # more importantly, to refuse a destination that points back at our own
    # short-link space (FR-006, "self_referential").
    config.x.short_domain = ENV.fetch("SHORT_DOMAIN")

    # Where the dashboard lives. The two server-rendered pages on the short
    # domain are the only place the backend has to link across to it, and a
    # relative link would point at the short domain, which serves no sign-up
    # page and never will.
    config.x.app_url = ENV.fetch("APP_URL")

    # Principle II. The naive Postgres-per-request redirect (T035) and the
    # cached one (T050) both stay in the tree and both stay runnable, so the
    # baseline can be re-measured after the optimisation exists rather than
    # being taken on trust from a commit nobody can run any more.
    #
    # This one carries a fallback where the connection settings deliberately do
    # not: an unset database URL is a misconfiguration, an unset feature flag is
    # the documented default. The default was false through 3A and 3B, when the
    # cache did not exist; from 3C it is true, because the cached path is the
    # product and the naive one is the measurement's subject. `load/serve.sh`
    # passes the flag explicitly either way, so a baseline re-run does not
    # depend on what this line says.
    config.x.redirect_cache_enabled = ActiveModel::Type::Boolean.new.cast(
      ENV.fetch("REDIRECT_CACHE_ENABLED", "true")
    )

    # T051. The redirect answers as early in the stack as it can while leaving
    # the guarantees that are not ours to drop.
    #
    # The task names `ActionDispatch::Session` as the thing to sit in front of;
    # this application has no session middleware at all (`api_only`, and the
    # note above about cookies), so the marker becomes `ActionDispatch::Executor`
    # — everything below it, from request-id generation and remote-IP resolution
    # to the reloader, the exception pages, `Rack::ETag` and the router itself,
    # is work a redirect does not need and now does not do.
    #
    # Not inserted at position 0: `ActionDispatch::SSL` and `ActionDispatch::Static`
    # stay in front, so a redirect is still upgraded to HTTPS in production and
    # a real file still wins over a code that spells its name.
    #
    # Being ahead of the executor is the reason the middleware wraps its own
    # miss path in `Rails.application.executor` — see the comment there.
    #
    # `app/middleware` moves to the once-autoloader because the stack is built
    # during initialization and holds one instance of this class for the life of
    # the process. A reloadable constant referenced there is the classic
    # "autoloading during initialization" mistake: the stack would keep the
    # instance of an obsolete class after the first reload, and every request
    # would run code the developer has already edited away.
    config.autoload_once_paths << "#{root}/app/middleware"

    initializer "backend.redirect_middleware", after: :load_config_initializers do |app|
      app.middleware.insert_before ActionDispatch::Executor, RedirectMiddleware
    end
  end
end
