# frozen_string_literal: true

require "rails_helper"

# T054, FR-022, SC-008. The constitution's durability ordering, made executable:
# Redis holds nothing that is a source of truth, so every way it can fail has to
# cost throughput or statistics — never a visitor's redirect, and never a wrong
# destination.
RSpec.describe "redirect resilience", :cached, type: :request do
  let(:link) { create(:link, destination_url: "https://example.com/destination") }

  # Fails one Redis command on a real connection rather than replacing the
  # client wholesale: the point is that the *rest* of the path still runs, and a
  # stub that answered nothing would prove that by not running it.
  def failing(command)
    allow(REDIS).to receive(:with).and_wrap_original do |original, *args, &block|
      original.call(*args) do |redis|
        allow(redis).to receive(command).and_raise(Redis::CannotConnectError, "simulated outage")

        block.call(redis)
      end
    end
  end

  describe "when the click cannot be buffered" do
    before { failing(:lpush) }

    # The response triple is built before the LPUSH is attempted, precisely so
    # that this is structurally true rather than a matter of ordering somebody
    # has to remember.
    it "still redirects the visitor" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://example.com/destination")
    end

    it "still forbids caching and sets no cookie" do
      get "/#{link.code}"

      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.headers["set-cookie"]).to be_nil
    end

    it "loses the click and nothing else" do
      get "/#{link.code}"

      expect(REDIS.with { |redis| redis.llen(RedirectMiddleware::CLICK_BUFFER_KEY) }).to eq(0)
      expect(link.reload.clicks_count).to eq(0)
    end
  end

  describe "when Redis is unreachable altogether" do
    before { failing(:getex) }

    # Principle II's second dividend: the naive path is still in the tree, so
    # "the cache is gone" degrades to "the cache is not there yet" rather than
    # to an outage.
    it "falls through to Postgres and answers correctly" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://example.com/destination")
    end

    it "answers the explanatory page for an unknown code rather than a 500" do
      get "/aB3xY9q"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Snip turns long web addresses")
    end
  end

  # The pool timing out is what a saturated Redis looks like from Ruby, and it
  # is not a Redis error — it is the failure most likely to arrive first under
  # the load this architecture is built for.
  describe "when every Redis connection is busy" do
    before do
      allow(REDIS).to receive(:with).and_raise(ConnectionPool::TimeoutError, "simulated saturation")
    end

    it "degrades to the Postgres path instead of failing the request" do
      get "/#{link.code}"

      expect(response).to have_http_status(:found)
    end
  end

  describe "when a flush loses its batch" do
    before do
      link
      get "/#{link.code}"
    end

    # D4's accepted trade, stated as a test: `LPOP` has already removed the
    # entries when the write fails, so those clicks are gone. What must not
    # happen is a counter that moved without rows behind it, or a link left in
    # any way unusable.
    it "costs the statistics for that batch and leaves the links untouched" do
      allow(Click).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "simulated failure")

      expect { Clicks::FlushJob.new.perform }.to raise_error(ActiveRecord::StatementInvalid)

      expect(link.reload.clicks_count).to eq(0)
      expect(Click.count).to eq(0)
    end

    it "keeps serving redirects afterwards, and counts the ones that follow" do
      allow(Click).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "simulated failure")

      suppress(ActiveRecord::StatementInvalid) { Clicks::FlushJob.new.perform }

      RSpec::Mocks.space.proxy_for(Click).reset

      get "/#{link.code}"
      Clicks::FlushJob.new.perform

      expect(link.reload.clicks_count).to eq(1)
    end
  end
end
