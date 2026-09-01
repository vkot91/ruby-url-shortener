# frozen_string_literal: true

require "rails_helper"

# contracts/redirect.md, against the naive implementation (T035).
#
# Everything asserted here has to keep holding when RedirectMiddleware takes the
# path over in 3C — this file is the contract, not the controller's spec, so it
# is the thing that catches a middleware that forgets a header.
RSpec.describe "GET /:code", type: :request do
  let(:link) { create(:link, destination_url: "https://example.com/destination") }

  describe "an active link" do
    before { get "/#{link.code}" }

    it "answers 302 Found, never 301 (D8, FR-016)" do
      expect(response).to have_http_status(:found)
    end

    it "sends the visitor to the current destination (FR-013)" do
      expect(response.headers["Location"]).to eq("https://example.com/destination")
    end

    # A cached redirect breaks destination editing — US3's whole promise —
    # for exactly the visitors who clicked before the edit. This header is
    # mandatory rather than advisory.
    it "forbids caching the mapping" do
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    # FR-015 and Principle V. ActionDispatch::Cookies is not in the stack, so
    # this is structural — and this is the path where it matters most.
    it "sets no cookie" do
      expect(response.headers["set-cookie"]).to be_nil
    end

    it "sends an empty body, since the visitor is not meant to stop here" do
      expect(response.body).to be_empty
    end
  end

  describe "an unknown code" do
    before { get "/notacode" }

    it "answers 404 (FR-017)" do
      expect(response).to have_http_status(:not_found)
    end

    # FR-017 asks for a page that explains the service, not a bare error: this
    # is the most common first contact an anonymous visitor has with the
    # product (design.md §6.9).
    it "explains what the service is rather than showing an error string" do
      expect(response.body).to include("This link doesn&rsquo;t exist").or include("This link doesn’t exist")
      expect(response.body).to include("Snip turns long web addresses")
    end

    it "sets no cookie and forbids caching" do
      expect(response.headers["set-cookie"]).to be_nil
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end
  end

  describe "a deleted link" do
    let(:link) { create(:link, :deleted) }

    # FR-028. Deleted means gone to a visitor, but the row and the code survive
    # so the statistics survive and the code is never handed to anyone else
    # (FR-029, D12).
    it "answers the not-found page rather than redirecting" do
      get "/#{link.code}"

      expect(response).to have_http_status(:not_found)
      expect(response.headers["Location"]).to be_nil
    end

    it "records no click for it" do
      expect { get "/#{link.code}" }.not_to(change { link.reload.clicks_count })
    end
  end

  # FR-018, and the resolution order in data-model.md: deleted is checked
  # before banned, so a link that is both reads as deleted.
  describe "a banned link" do
    let(:link) { create(:link, :banned) }

    it "answers 403 rather than redirecting" do
      get "/#{link.code}"

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Location"]).to be_nil
    end
  end

  describe "a link of a banned account" do
    let(:link) { create(:link, account: create(:account, :banned)) }

    it "answers 403 without the link itself being banned" do
      get "/#{link.code}"

      expect(response).to have_http_status(:forbidden)
      expect(link.reload).not_to be_banned
    end
  end

  # FR-020. Naively and synchronously in 3A; 3C moves it off the request path
  # entirely (T053) and this expectation stays true.
  describe "click counting" do
    it "counts every redirect it serves" do
      expect { 3.times { get "/#{link.code}" } }.to change { link.reload.clicks_count }.from(0).to(3)
    end

    it "records a click row carrying the link and the time and nothing else" do
      get "/#{link.code}"

      click = Click.sole

      expect(click.link_id).to eq(link.id)
      expect(click.occurred_at).to be_within(5.seconds).of(Time.current)
      expect(Click.column_names).to match_array(%w[id link_id occurred_at])
    end
  end

  # FR-012, from the other side: a reserved segment must reach the router's
  # claim on it and never a code lookup.
  describe "reserved and non-code paths" do
    it "leaves /up to the health check rather than treating it as a code" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end

    it "does not treat a two-character path as a code" do
      get "/ab"

      expect(response).to have_http_status(:not_found)
    end

    it "does not treat a path with a hyphen in it as a code" do
      get "/not-a-code"

      expect(response).to have_http_status(:not_found)
    end
  end

  # FR-017 again, for the paths that never reach a lookup at all. A truncated
  # short link and a mistyped one are the same situation to the person who
  # typed it, so they get the same page — and without the catch-all they got
  # Rails' default 404 instead, which on an application with no
  # public/404.html is an empty body.
  describe "paths that could never have been a code" do
    {
      "a two-character path" => "/ab",
      "a path with a hyphen in it" => "/not-a-code",
      "a path with several segments" => "/some/deep/path",
      "the bare root" => "/"
    }.each do |description, path|
      it "answers the explanatory page for #{description}" do
        get path

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include("Snip turns long web addresses")
      end
    end

    it "answers it for a non-GET method too, rather than a routing error" do
      post "/not-a-code"

      expect(response).to have_http_status(:not_found)
    end

    it "sets no cookie and forbids caching, exactly as the code path does" do
      get "/ab"

      expect(response.headers["set-cookie"]).to be_nil
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end
  end

  # The other half of the catch-all. An API client that mistypes a path parses
  # JSON, and a page about short links is not something it can do anything
  # with.
  describe "an unclaimed path under /api" do
    before { get "/api/v1/nonexistent" }

    it "answers the JSON error envelope, not the HTML page" do
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end

    it "does not demand a token before admitting the path does not exist" do
      expect(response.parsed_body.dig("error", "code")).not_to eq("unauthenticated")
    end
  end
end
