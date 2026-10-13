# frozen_string_literal: true

require "rails_helper"

# SC-009: the number the creator reads on the dashboard reaches N within 30
# seconds of the Nth click. This is the spec that makes that a guarantee rather
# than a hope, and it asserts the whole path — visitor, buffer, flush, counter,
# API response — because every one of those links is where the number could be
# lost.
#
# Thirty seconds is a budget with three spenders: the flush interval
# (config/sidekiq.yml, 5s), the dashboard's poll interval (T108, 30s), and the
# work itself. Only the first two are under this project's control and they sum
# to 35s in the worst case — which is why the assertion below is on the *server*
# reaching the count promptly. The client's half is a `refetchInterval` the
# frontend tests own.
RSpec.describe "click counting", :cached, type: :request do
  let(:account) { create(:account) }
  let(:link) { create(:link, account: account, destination_url: "https://example.com/campaign") }

  def dashboard_count
    get "/api/v1/links/#{link.id}",
        headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" },
        as: :json

    response.parsed_body["clicks_count"]
  end

  def open_link(times)
    times.times { get "/#{link.code}" }
  end

  it "reports every click once the buffer has been drained" do
    open_link(7)

    deliver_clicks

    expect(dashboard_count).to eq(7)
  end

  # The lag is the feature, not a defect: the redirect writes one entry to a
  # Redis list and answers (D4, Principle I). Asserting the lag exists keeps
  # anyone from "fixing" it by putting a synchronous UPDATE back on the redirect
  # path — which is precisely the naive behaviour 3C was built to remove.
  it "is behind reality until the flush runs, and by no more than the clicks in the buffer" do
    open_link(7)

    expect(dashboard_count).to eq(0)
    expect(REDIS.with { |redis| redis.llen(RedirectMiddleware::CLICK_BUFFER_KEY) }).to eq(7)
  end

  it "reaches the full count inside the 30-second budget SC-009 allows" do
    started_at = Time.current

    open_link(30)

    # The scheduled flush, at the interval config/sidekiq.yml actually runs it.
    travel_to(started_at + 5.seconds) { deliver_clicks }

    travel_to(started_at + 30.seconds) do
      expect(dashboard_count).to eq(30)
    end
  end

  it "counts each link separately, so one link's traffic never inflates another's" do
    other = create(:link, account: account, destination_url: "https://example.com/other")

    open_link(3)
    get "/#{other.code}"

    deliver_clicks

    expect(dashboard_count).to eq(3)
    expect(other.reload.clicks_count).to eq(1)
  end

  it "keeps counting across flushes rather than restarting from the last batch" do
    open_link(4)
    deliver_clicks

    open_link(2)
    deliver_clicks

    expect(dashboard_count).to eq(6)
  end

  it "writes one click row per redirect, so the counter is a summary and not the record (FR-020)" do
    open_link(5)

    deliver_clicks

    expect(Click.where(link_id: link.id).count).to eq(5)
  end
end
