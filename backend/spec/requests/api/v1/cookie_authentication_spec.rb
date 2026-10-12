# frozen_string_literal: true

require "rails_helper"

# research.md D10, as amended. The browser's access token arrives as a cookie
# the Next.js BFF set on a domain both origins share; a mobile app or a CLI
# still sends the same token in `Authorization: Bearer`.
#
# The amendment is worth a spec of its own because "accepts a cookie" is one
# sentence away from "accepts a second kind of credential". There is one
# credential here — the signed access token — read from whichever of two places
# the client had available, and every example below exists to hold that line.
RSpec.describe "authentication by cookie", type: :request do
  let(:account) { create(:account) }
  let(:token) { Auth::AccessToken.encode(account) }
  let!(:link) { create(:link, account: account) }

  def get_links(headers)
    get "/api/v1/links", headers: headers
  end

  def with_cookie(value) = { "HTTP_COOKIE" => "#{Authentication::ACCESS_COOKIE}=#{value}" }

  it "authenticates a browser that sends the access token as a cookie" do
    get_links(with_cookie(token))

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["links"].pluck("id")).to contain_exactly(link.id)
  end

  it "still authenticates a client that sends the header, which is what a CLI has" do
    get_links("Authorization" => "Bearer #{token}")

    expect(response).to have_http_status(:ok)
  end

  # The header is the one a client had to construct on purpose; a cookie rides
  # along by itself and cannot express intent.
  it "prefers the header when a client somehow sends both" do
    other = create(:account)

    get_links(with_cookie(Auth::AccessToken.encode(other)).merge("Authorization" => "Bearer #{token}"))

    expect(response.parsed_body["links"].pluck("id")).to contain_exactly(link.id)
  end

  describe "the cookie is not a credential of its own" do
    it "verifies the signature exactly as it does for the header" do
      get_links(with_cookie("#{token}tampered"))

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    # The whole client-side design rests on this code being distinguishable:
    # `token_expired` means "refresh and retry", and it is the only thing that
    # makes a refresh happen at all now.
    it "reports an aged-out cookie as token_expired, not as unauthenticated" do
      aged = Auth::AccessToken.encode(account)

      travel_to(Auth::AccessToken::LIFETIME.from_now + 1.second) { get_links(with_cookie(aged)) }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("token_expired")
    end

    it "refuses an empty cookie the same way it refuses no credential at all" do
      get_links(with_cookie(""))

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end
  end

  # FR-015 and Principle V, still structural — and note what the principle
  # actually governs: what is *set* on the redirect path, not what happens to
  # arrive there. Reading a cookie is Rack parsing the request header; it does
  # not put ActionDispatch::Cookies in the stack and therefore does not give
  # this application the ability to set one.
  describe "reading a cookie does not grant setting one" do
    it "keeps the cookie middleware out of the stack" do
      expect(Rails.application.middleware.map(&:name)).not_to include("ActionDispatch::Cookies")
    end

    it "sets no cookie on an authenticated API response" do
      get_links(with_cookie(token))

      expect(response.headers["set-cookie"]).to be_nil
    end

    it "sets no cookie on a redirect, whatever the visitor sends", :cached do
      get "/#{link.code}", headers: with_cookie(token)

      expect(response).to have_http_status(:found)
      expect(response.headers["set-cookie"]).to be_nil
    end
  end
end
