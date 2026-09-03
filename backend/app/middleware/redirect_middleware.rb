# frozen_string_literal: true

# The redirect path (T050, T053, D1, contracts/redirect.md).
#
# Rack middleware rather than a controller because Principle I forbids
# non-essential synchronous work here, and a controller action is nothing but
# non-essential work for this response: request object allocation, parameter
# parsing, callbacks, an ActiveRecord instance, a view lookup. None of it is
# needed to turn seven characters into a `Location` header. What is left is
# Puma → Rack → one Redis `GETEX`.
#
# This is also where the Principle I waiver taken for 3A expires. From here the
# gate conditions in contracts/redirect.md are enforceable and enforced:
# no Postgres on a cache hit, no `Set-Cookie` on any outcome, no analytics
# enrichment, no rate limiter.
#
# The naive controller stays in the tree and stays reachable with
# `REDIRECT_CACHE_ENABLED=false` (Principle II) — the baseline has to be
# re-runnable against the same checkout that carries the optimisation, or the
# comparison rests on a commit nobody can execute any more.
class RedirectMiddleware
  # The same pattern contracts/redirect.md states and config/routes.rb draws.
  # Anything else — a hyphen, a second segment, a two-character path — is not a
  # code and is handed to the router, which owns the explanatory 404.
  CODE_PATTERN = %r{\A/([A-Za-z0-9]{3,32})\z}

  # A redirect answers GET, and HEAD because Rack::Head is downstream of here
  # and would not otherwise see this response at all.
  ANSWERABLE_METHODS = %w[GET HEAD].freeze

  # data-model.md: `clicks:buffer`, in db0 with the cache rather than in
  # Sidekiq's db1. The buffer is expendable and belongs next to the other
  # expendable state; the job queue is not (D9).
  CLICK_BUFFER_KEY = "clicks:buffer"

  NO_STORE = "no-store"

  # config/initializers/redis.rb, where the pool this rescues around is built.
  DEGRADED_ERRORS = REDIS_UNAVAILABLE_ERRORS

  def initialize(app)
    @app = app
  end

  def call(env)
    code = redirect_code(env)

    return @app.call(env) if code.nil?

    serve(code)
  rescue *DEGRADED_ERRORS => error
    # Redis is the cache, not the system of record. Losing it must cost
    # throughput, not correctness (SC-008), so the request falls through to the
    # router and the naive Postgres path answers it.
    log_degraded(error)

    @app.call(env)
  end

  private

  # Everything that can disqualify a request before Redis is asked, in the order
  # that costs least: a flag read, a string compare, a regexp, a set lookup.
  def redirect_code(env)
    return nil unless enabled?
    return nil unless ANSWERABLE_METHODS.include?(env["REQUEST_METHOD"])

    match = CODE_PATTERN.match(env["PATH_INFO"])

    return nil if match.nil?

    code = match[1]

    # `/up` and `/api` match the code pattern and belong to the router (FR-012).
    # Creation refuses them as codes, so no link can shadow one; this is the
    # other half of that guarantee, from the reading side.
    return nil if Rails.application.config.x.reserved_codes.include?(code.downcase)

    code
  end

  def enabled? = Rails.application.config.x.redirect_cache_enabled

  def serve(code)
    raw = Cache::LinkCache.read(code)
    raw = resolve_and_cache(code) if raw.nil?

    return not_found if Cache::NegativeCache.absent?(raw)

    entry = Cache::LinkCache.unpack(raw)

    # data-model.md's resolution order, and it is not arbitrary: a link that is
    # both deleted and banned reads as deleted, because its owner deleted it and
    # a warning page would tell a visitor something about a link that no longer
    # exists.
    return not_found if entry.deleted?
    return blocked if entry.blocked?

    redirect(entry)
  end

  # The 1–5% of requests the whole design is arranged around not being: this is
  # the only branch that touches Postgres, and it is wrapped in the executor
  # because the middleware sits ahead of `ActionDispatch::Executor` in the stack
  # (config/application.rb). Without the wrapper the ActiveRecord connection
  # checked out here would never be returned to the pool.
  def resolve_and_cache(code)
    Rails.application.executor.wrap do
      Cache::SingleFlight.resolve(code, read: -> { Cache::LinkCache.read(code) }) do
        entry = load_entry(code)

        if entry.nil?
          Cache::NegativeCache.write(code)
          Cache::NegativeCache::SENTINEL
        else
          Cache::LinkCache.write(code, entry)
          Cache::LinkCache.pack(entry)
        end
      end
    end
  end

  # One query, not two: the owning account's ban is part of the redirect
  # decision (FR-018), and `link.account.banned_at` would make the miss path pay
  # a second round trip for one boolean. Raw values rather than an ActiveRecord
  # object because nothing here needs a model — this is the only Postgres access
  # on the redirect path and it stays as small as the decision it feeds.
  def load_entry(code)
    row = Link
      .joins(:account)
      .where(code: code)
      .pick("links.id", "links.destination_url", "links.banned_at", "links.deleted_at",
            "links.account_id", "accounts.banned_at")

    return nil if row.nil?

    id, destination_url, banned_at, deleted_at, account_id, account_banned_at = row

    Cache::LinkCache::Entry.new(
      link_id: id,
      destination_url: destination_url,
      banned: banned_at.present?,
      deleted: deleted_at.present?,
      account_banned: account_banned_at.present?,
      account_id: account_id
    )
  end

  def redirect(entry)
    # Built before the click is recorded, and returned whatever the recording
    # does (FR-021, FR-022). The statistics are downstream of the response in
    # both senses.
    response = [
      302,
      { "location" => entry.destination_url, "cache-control" => NO_STORE },
      []
    ]

    record_click(entry.link_id)

    response
  end

  # T053, D4. One `LPUSH` of a string, drained by Clicks::FlushJob every five
  # seconds — replacing 3A's two synchronous Postgres statements per redirect,
  # which the 3B baseline named as ~62% of the SQL time on a path that needed
  # none of it before answering.
  #
  # `Time.now` rather than `Time.current`: the zone conversion is pure overhead
  # for a value that is about to be serialised as epoch milliseconds anyway.
  def record_click(link_id)
    REDIS.with do |redis|
      redis.lpush(CLICK_BUFFER_KEY, "#{link_id}:#{(Time.now.to_f * 1000).round}")
    end
  rescue *DEGRADED_ERRORS => error
    # A visitor's redirect does not fail because a counter could not be
    # incremented. Losing clicks costs statistics and nothing else (SC-008), and
    # the constitution's durability ordering is explicit that this is the trade
    # to make.
    log_degraded(error)
  end

  def not_found
    [ 404, html_headers, [ self.class.not_found_page ] ]
  end

  # FR-018. The full warning page with its report control is T084 in Phase 6;
  # until then this is the same body the naive controller sends, so moving the
  # path from one to the other changes nothing a visitor sees.
  def blocked
    body = "This link has been blocked."

    [ 403, { "content-type" => "text/plain; charset=utf-8", "cache-control" => NO_STORE,
             "content-length" => body.bytesize.to_s }, [ body ] ]
  end

  def html_headers
    {
      "content-type" => "text/html; charset=utf-8",
      "cache-control" => NO_STORE,
      "content-length" => self.class.not_found_page.bytesize.to_s
    }
  end

  # Rendered once, not per request. The page has no request-dependent content —
  # its only interpolation is the dashboard URL out of the application config —
  # so rendering it on every unknown code would be a view lookup and an ERB
  # evaluation added to the path that enumeration attacks hit hardest.
  def self.not_found_page
    @not_found_page ||= RedirectsController.render("pages/not_found", layout: false, formats: [ :html ]).freeze
  end

  def log_degraded(error)
    Rails.logger.warn(JSON.generate(event: "redirect_cache_degraded", error: error.class.name))
  end
end
