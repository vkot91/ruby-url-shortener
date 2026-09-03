# frozen_string_literal: true

require "rails_helper"

# T052. The gate conditions in contracts/redirect.md, asserted rather than
# asserted-to: "no synchronous Postgres query on a cache hit; no `Set-Cookie`;
# no analytics enrichment; no per-request logging beyond one structured line."
#
# Principle I is the whole reason this application is shaped the way it is, and
# a principle that is only reviewed by eye is a principle that lasts until the
# first hurried change. This file is the mechanism that catches that change.
RSpec.describe RedirectMiddleware, :cached, type: :request do
  let(:link) { create(:link, destination_url: "https://example.com/destination") }

  # Counts what actually reached Postgres, ignoring the transaction and schema
  # statements Rails issues around it — the claim is about the *work* the path
  # does, not about the connection it does it on.
  def postgres_statements
    statements = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end

    yield

    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "a cache hit" do
    # The first request is the miss that populates the cache; every assertion
    # below is about the second one, which is the request 95–99% of visitors
    # make.
    before { get "/#{link.code}" }

    it "reaches Postgres not at all" do
      statements = postgres_statements { get "/#{link.code}" }

      expect(statements).to be_empty
    end

    it "still answers 302 to the destination" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://example.com/destination")
    end

    it "forbids caching the mapping (D8, FR-016)" do
      get "/#{link.code}"

      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    # FR-015, Principle V. Structural — there is no cookie middleware in the
    # stack — but this path is where it matters, so it is asserted where it
    # matters rather than trusted.
    it "sets no cookie" do
      get "/#{link.code}"

      expect(response.headers["set-cookie"]).to be_nil
      expect(response.headers["Set-Cookie"]).to be_nil
    end

    it "sends an empty body, since the visitor is not meant to stop here" do
      get "/#{link.code}"

      expect(response.body).to be_empty
    end

    # D6, from the outside: the entry a visitor just used must not be closer to
    # expiry for their having used it.
    it "pushes the entry's expiry back out rather than letting it run down" do
      REDIS.with { |redis| redis.expire(Cache::LinkCache.key(link.code), 60) }

      get "/#{link.code}"

      ttl = REDIS.with { |redis| redis.ttl(Cache::LinkCache.key(link.code)) }

      expect(ttl).to be_within(5).of(Cache::LinkCache::TTL.to_i)
    end
  end

  describe "a cache miss" do
    it "answers from Postgres and populates the cache for everyone behind it" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
      expect(Cache::LinkCache.read(link.code)).to be_present
    end

    it "reads the link and its account's ban in one statement, not two" do
      code = link.code # created before the measurement, not inside it

      statements = postgres_statements { get "/#{code}" }

      expect(statements.size).to eq(1)
      expect(statements.first).to include("accounts")
    end

    # D5, SC-007. The winner of the lock rebuilds; nobody else does. Asserted
    # here on the single-request case — that the lock is taken at all — with the
    # concurrent case measured under load in load/stampede.js (T061).
    it "takes the rebuild lock so a stampede cannot follow it" do
      get "/#{link.code}"

      expect(REDIS.with { |redis| redis.get(Cache::SingleFlight.lock_key(link.code)) }).to be_present
    end
  end

  describe "an unknown code" do
    it "answers the explanatory page rather than an error string (FR-017)" do
      get "/aB3xY9q"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Snip turns long web addresses")
    end

    it "sets no cookie and forbids caching" do
      get "/aB3xY9q"

      expect(response.headers["set-cookie"]).to be_nil
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    # SC-007. Somebody walking the code space gets one Postgres query per code,
    # not one per request — which is what keeps enumeration a flat line on the
    # database rather than a slope.
    it "remembers the absence, so a second attempt at the same code costs nothing" do
      get "/aB3xY9q"

      statements = postgres_statements { get "/aB3xY9q" }

      expect(statements).to be_empty
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a deleted link" do
    let(:link) { create(:link, :deleted) }

    # FR-028 and data-model.md's resolution order: deleted is checked before
    # banned, so a link that is both reads as gone.
    it "answers the not-found page rather than redirecting" do
      get "/#{link.code}"

      expect(response).to have_http_status(:not_found)
      expect(response.headers["Location"]).to be_nil
    end

    it "answers it from the cache on the second request too" do
      get "/#{link.code}"

      statements = postgres_statements { get "/#{link.code}" }

      expect(statements).to be_empty
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a banned link" do
    let(:link) { create(:link, :banned) }

    it "answers 403 rather than redirecting (FR-018)" do
      get "/#{link.code}"

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Location"]).to be_nil
    end
  end

  describe "a link of a banned account" do
    let(:link) { create(:link, account: create(:account, :banned)) }

    # The account's ban is part of the cached value, which is why the hot path
    # can honour it without a second key and a second round trip (D14).
    it "answers 403 without a Postgres read on the second request" do
      get "/#{link.code}"

      statements = postgres_statements { get "/#{link.code}" }

      expect(response).to have_http_status(:forbidden)
      expect(statements).to be_empty
    end
  end

  describe "what the middleware refuses to answer" do
    # FR-012. `/up` matches the code pattern character for character, and the
    # health check would disappear behind a 404 the first time anybody deployed
    # this.
    it "leaves a reserved path to the router" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end

    it "leaves a path that could not be a code to the router" do
      get "/not-a-code"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Snip turns long web addresses")
    end

    # A short link is followed with GET. Anything else is not a redirect and
    # belongs to the application behind it — including the report endpoint that
    # will share this path shape in Phase 6.
    it "leaves a non-GET request to the router" do
      post "/#{link.code}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "invalidation (T058, Principle IV)" do
    # US3's core promise, one phase early because the cache is what threatens
    # it: an edit that does not reach Redis is an edit that silently did not
    # happen for the next 24 hours.
    it "sends the next visitor to the new destination immediately after an edit" do
      get "/#{link.code}"

      link.update!(destination_url: "https://example.com/moved")

      get "/#{link.code}"

      expect(response.headers["Location"]).to eq("https://example.com/moved")
    end

    it "resolves a code that was probed before it existed" do
      get "/aB3xY9q"

      create(:link, code: "aB3xY9q", destination_url: "https://example.com/new")

      get "/aB3xY9q"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://example.com/new")
    end
  end
end
