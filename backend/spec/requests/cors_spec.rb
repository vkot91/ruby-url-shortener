# frozen_string_literal: true

require "rails_helper"

# research.md D10's unavoidable consequence: the dashboard is a different origin
# from the API, so a bearer token crosses an origin boundary on every
# authenticated request and the browser refuses to send it without these
# headers.
#
# Two halves, and the second is the one worth having a spec for. Opening CORS is
# easy to get right and easy to over-open, so what is asserted here is mostly
# what stays *closed*: one origin, one path prefix, no credentials, and nothing
# at all on the redirect path.
RSpec.describe "CORS", type: :request do
  let(:app_origin) { Rails.application.config.x.app_url }
  let(:account) { create(:account) }

  def preflight(path, origin: app_origin, method: "GET")
    process(:options, path, headers: {
      "Origin" => origin,
      "Access-Control-Request-Method" => method,
      "Access-Control-Request-Headers" => "authorization,content-type"
    })
  end

  describe "the dashboard's origin" do
    it "is allowed to preflight an authenticated request" do
      preflight("/api/v1/links")

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(app_origin)
    end

    it "is allowed to send the Authorization header, which is the whole point" do
      preflight("/api/v1/links")

      expect(response.headers["Access-Control-Allow-Headers"]).to include("authorization")
    end

    it "is allowed every method the API answers" do
      preflight("/api/v1/links")

      expect(response.headers["Access-Control-Allow-Methods"].to_s.upcase)
        .to include("GET", "POST", "PATCH", "DELETE")
    end

    it "marks an actual request as readable by the browser that made it" do
      get "/api/v1/links",
          headers: {
            "Origin" => app_origin,
            "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}"
          }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(app_origin)
    end
  end

  describe "every other origin" do
    # The reason `origins "*"` is not in the initializer. A wildcard would let
    # any page on the internet read this API with a token it had obtained by
    # some other means; naming one origin means the browser refuses to hand the
    # response over.
    it "is refused, so a stolen token cannot be spent from a page we did not write" do
      preflight("/api/v1/links", origin: "https://evil.example")

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end

    it "gets no allowance on an actual request either" do
      get "/api/v1/links",
          headers: {
            "Origin" => "https://evil.example",
            "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}"
          }

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end

  # Credentials are on, because the browser's access token is a cookie and it
  # would not otherwise be attached to a cross-origin request (research.md D10,
  # as amended). It is safe only in company with the named origin above: the two
  # together are what stop another page reading this API with the visitor's own
  # cookie, and browsers refuse the `*` + credentials combination outright.
  it "allows credentials, so the browser attaches the access cookie" do
    get "/api/v1/links",
        headers: {
          "Origin" => app_origin,
          "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}"
        }

    expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
  end

  it "never allows credentials to a wildcard, which would hand the API to any page" do
    expect(Rails.application.config.x.cors_origins).not_to include("*")
  end

  # Principle I, structurally. Rack::Cors is inserted *after* RedirectMiddleware
  # (config/application.rb), so a cached redirect is answered and returned
  # before the CORS middleware exists — it cannot add a header here even if the
  # rules were widened to match `/`. A redirect is a navigation, and the
  # same-origin policy does not govern navigations.
  describe "the redirect path" do
    let!(:link) { create(:link, destination_url: "https://example.com/destination") }

    it "answers a cached redirect with no CORS header, whatever Origin claims", :cached do
      get "/#{link.code}", headers: { "Origin" => app_origin }

      expect(response).to have_http_status(:found)
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end

    it "answers the naive redirect the same way" do
      get "/#{link.code}", headers: { "Origin" => app_origin }

      expect(response).to have_http_status(:found)
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end
end
