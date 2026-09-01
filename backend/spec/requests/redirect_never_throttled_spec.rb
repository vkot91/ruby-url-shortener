# frozen_string_literal: true

require "rails_helper"

# FR-019 and Principle I. Redirect traffic is never rate-limited, never gated on
# the account's plan, and never blocked by anything the owner has done to their
# own quota.
#
# The reason this is its own file rather than one example inside the redirect
# spec: a limiter is the sort of thing someone adds later, in a hurry, because
# the redirect path is where the traffic is and throttling it looks like an
# obvious lever. It is the one path where that lever must not exist. A visitor
# clicking a link has no relationship with the account that made it and cannot
# be punished for its behaviour.
RSpec.describe "Redirects are never throttled", type: :request do
  let(:account) { create(:account) }
  let(:link) { create(:link, account: account) }

  def create_link_via_api(destination)
    post "/api/v1/links",
         params: { destination_url: destination },
         headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" },
         as: :json
  end

  it "serves an account that is far over its link cap" do
    create_list(:link, Account::FREE_LINK_LIMIT + 10, account: account)

    create_link_via_api("https://example.com/one-too-many")
    expect(response.parsed_body.dig("error", "code")).to eq("link_limit_reached")

    get "/#{link.code}"

    expect(response).to have_http_status(:found)
  end

  it "serves an account that has exhausted its hourly creation limit" do
    31.times { |n| create_link_via_api("https://example.com/#{n}") }

    expect(response).to have_http_status(:too_many_requests)

    get "/#{link.code}"

    expect(response).to have_http_status(:found)
  end

  it "serves the same visitor a hundred times in a row without slowing or refusing" do
    100.times { get "/#{link.code}" }

    expect(response).to have_http_status(:found)
    expect(link.reload.clicks_count).to eq(100)
  end

  it "serves a visitor whose address has been throttled on an authentication endpoint" do
    11.times { post "/api/v1/registrations", params: { email: "a#{_1}@example.com", password: "a-sufficiently-long-passphrase" }, as: :json }

    expect(response).to have_http_status(:too_many_requests)

    get "/#{link.code}"

    expect(response).to have_http_status(:found)
  end

  # The structural version of the same guarantee. Rails' `rate_limit` is a
  # `before_action`, so a limiter on this controller would be a callback on it —
  # and a callback is something this spec can look for directly rather than
  # inferring from behaviour that happens to pass today.
  it "has no rate-limiting callback on the redirect controller at all" do
    callbacks = RedirectsController._process_action_callbacks.map(&:filter)

    expect(callbacks).to be_empty
  end
end
