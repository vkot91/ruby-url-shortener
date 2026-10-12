# frozen_string_literal: true

require "rails_helper"

# SC-008, FR-022. spec/middleware/redirect_resilience_spec.rb fails one Redis
# command at a time, which is what a degraded Redis looks like. This spec is the
# other shape of the same failure: the server is *gone*, every command raises,
# and the question is whether the product still works.
#
# The answer the constitution requires is that it does, more slowly. That is
# asserted here across both surfaces a person touches — the visitor's redirect
# and the creator's dashboard — because a redirect path that survives an outage
# behind a dashboard that 500s is still an outage to the account holder looking
# at it.
RSpec.describe "a total Redis outage", :cached, type: :request do
  let(:account) { create(:account) }
  let!(:link) { create(:link, account: account, destination_url: "https://example.com/destination") }

  # Refusing at the pool rather than at the client. A stopped server is not a
  # connection that answers errors — it is one that cannot be checked out at
  # all, which is the failure the connection pool surfaces first and the one a
  # `rescue Redis::BaseError` alone would miss.
  def stop_redis
    allow(REDIS).to receive(:with).and_raise(ConnectionPool::TimeoutError, "simulated outage")
  end

  def token = "Bearer #{Auth::AccessToken.encode(account)}"

  describe "the visitor's redirect (Principle I)" do
    before { stop_redis }

    it "still answers, and with the right destination" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://example.com/destination")
    end

    it "still refuses to be cached and still sets no cookie (Principle V)" do
      get "/#{link.code}"

      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.headers["set-cookie"]).to be_nil
    end

    it "still answers a banned link with the safety page rather than the destination (FR-018)" do
      banned = create(:link, :banned, account: account)

      stop_redis

      get "/#{banned.code}"

      expect(response).not_to have_http_status(:found)
    end

    it "still answers an unknown code with the explanatory page, not a 500 (FR-017)" do
      get "/aB3xY9q"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the creator's dashboard" do
    before { stop_redis }

    # Authentication is signature verification and the list is one Postgres
    # query, so neither has anything to ask Redis (research.md D10, driver 3).
    # This asserts that rather than assuming it: an authentication cache added
    # later would pass its own specs and fail this one.
    it "still lists the account's links" do
      get "/api/v1/links", headers: { "Authorization" => token }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["links"].pluck("id")).to contain_exactly(link.id)
    end

    it "still fetches a single link" do
      get "/api/v1/links/#{link.id}", headers: { "Authorization" => token }, as: :json

      expect(response).to have_http_status(:ok)
    end

    # `update_counters`, which is how the flush job moves this column and the
    # only way to move it here: an ordinary `update!` would try to invalidate
    # the cache from an after_commit hook and fail against the stopped server.
    it "still reports the count Postgres already holds" do
      # rubocop:disable Rails/SkipsModelValidations
      Link.update_counters(link.id, clicks_count: 41)
      # rubocop:enable Rails/SkipsModelValidations

      get "/api/v1/links/#{link.id}", headers: { "Authorization" => token }, as: :json

      expect(response.parsed_body["clicks_count"]).to eq(41)
    end
  end

  # The cost, stated so that it is a decision on the record rather than a
  # surprise. It is smaller than it looks, and only because Principle II kept
  # the naive path in the tree: the middleware rescues, the router takes the
  # request, and RedirectsController answers it out of Postgres — buffering
  # included, since Clicks::Recorder writes the click synchronously.
  describe "what the outage does cost" do
    it "costs throughput, not clicks — the naive Postgres path counts them (Principle II)" do
      stop_redis

      3.times { get "/#{link.code}" }

      expect(link.reload.clicks_count).to eq(3)
      expect(Click.where(link_id: link.id).count).to eq(3)
    end

    it "buffers nothing, because there is nowhere to buffer to" do
      stop_redis

      get "/#{link.code}"

      expect { deliver_clicks }.to raise_error(ConnectionPool::TimeoutError)
    end

    # The asymmetry Link#invalidate_cache documents, asserted rather than
    # described: an acknowledged edit that left visitors going to the old
    # destination for the next 24 hours is the one failure Principle IV forbids
    # outright, so the edit fails instead.
    it "refuses an edit rather than acknowledging one it cannot make true (Principle IV)" do
      stop_redis

      expect { link.update!(destination_url: "https://example.com/elsewhere") }
        .to raise_error(ConnectionPool::TimeoutError)
    end

    it "resumes buffering the moment Redis comes back, without a restart" do
      stop_redis
      get "/#{link.code}"

      RSpec::Mocks.space.proxy_for(REDIS).reset

      get "/#{link.code}"
      deliver_clicks

      expect(link.reload.clicks_count).to eq(2)
    end
  end
end
