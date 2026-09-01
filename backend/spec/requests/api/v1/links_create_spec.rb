# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/links", type: :request do
  let(:account) { create(:account) }

  def create_link(params)
    post "/api/v1/links",
         params: params,
         headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" },
         as: :json
  end

  def error_code = response.parsed_body.dig("error", "code")

  describe "success" do
    before { create_link(destination_url: "https://example.com/a-very-long-campaign-address?utm_source=poster", name: "Spring poster") }

    it "returns the Link schema from contracts/openapi.yaml" do
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.keys)
        .to match_array(%w[id code short_url destination_url name clicks_count created_at])
    end

    it "issues a 7-character code of letters and digits (FR-009)" do
      expect(response.parsed_body["code"]).to match(/\A[A-Za-z0-9]{7}\z/)
    end

    it "builds the short URL on the short domain, not on the API's own host" do
      code = response.parsed_body["code"]

      expect(response.parsed_body["short_url"]).to eq("https://#{Rails.application.config.x.short_domain}/#{code}")
    end

    it "stores the destination normalised (FR-008), keeping the tracking parameters" do
      expect(response.parsed_body["destination_url"])
        .to eq("https://example.com/a-very-long-campaign-address?utm_source=poster")
    end

    it "starts the counter at zero" do
      expect(response.parsed_body["clicks_count"]).to eq(0)
    end

    it "belongs to the caller and to nobody else (FR-002)" do
      expect(Link.find(response.parsed_body["id"]).account).to eq(account)
    end
  end

  it "accepts a link with no name, since the name is a creator-facing label" do
    create_link(destination_url: "https://example.com/x")

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["name"]).to be_nil
  end

  it "requires authentication" do
    post "/api/v1/links", params: { destination_url: "https://example.com/x" }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # contracts/openapi.yaml lists six reasons a creation can be refused, and the
  # create form maps each to a message beside the right field (design.md §6.4,
  # P5). A reason that arrives as a generic 422 is a reason the form cannot
  # explain, so all six are asserted here by name.
  describe "the six rejection reasons" do
    it "invalid_url — a destination that is not an address at all" do
      create_link(destination_url: "http://exa mple.com")

      expect(response).to have_http_status(:unprocessable_content)
      expect(error_code).to eq("invalid_url")
    end

    it "unsupported_scheme — anything that is not http or https" do
      create_link(destination_url: "ftp://example.com/file")

      expect(error_code).to eq("unsupported_scheme")
    end

    # The scheme unit tests pass on a URL that never used to get this far. A
    # scheme with no `//` after it was read as a schemeless hostname, prefixed
    # with `https://`, and refused by the normalizer as `invalid_url` — so the
    # whole of Urls::SafetyValidator's scheme handling was unreachable from
    # here. Asserting the code end to end, not only in the unit spec, is what
    # catches that.
    it "unsupported_scheme — including a scheme with no authority after it" do
      create_link(destination_url: "data:text/html,<script>alert(1)</script>")

      expect(error_code).to eq("unsupported_scheme")
    end

    it "unsupported_scheme — including javascript:" do
      create_link(destination_url: "javascript:alert(1)")

      expect(error_code).to eq("unsupported_scheme")
    end

    it "private_address — a host resolving off the public internet (FR-006)" do
      resolve_all_hosts_to("169.254.169.254")

      create_link(destination_url: "https://looks-fine.example/x")

      expect(error_code).to eq("private_address")
    end

    it "self_referential — a short link pointing at our own short domain" do
      create_link(destination_url: "https://#{Rails.application.config.x.short_domain}/abc1234")

      expect(error_code).to eq("self_referential")
    end

    it "blocked_domain — a domain on the platform blocklist (FR-007)" do
      BlockedDomain.create!(domain: "malware.example")

      create_link(destination_url: "https://malware.example/payload")

      expect(error_code).to eq("blocked_domain")
    end

    it "blocked_domain — and its subdomains too" do
      BlockedDomain.create!(domain: "malware.example")

      create_link(destination_url: "https://cdn.tracking.malware.example/payload")

      expect(error_code).to eq("blocked_domain")
    end

    it "link_limit_reached — a free account at its fifty-link ceiling (FR-004)" do
      create_list(:link, Account::FREE_LINK_LIMIT, account: account)

      create_link(destination_url: "https://example.com/one-too-many")

      expect(error_code).to eq("link_limit_reached")
    end

    it "counts only live links towards the ceiling, so deleting one frees the slot" do
      create_list(:link, Account::FREE_LINK_LIMIT - 1, account: account)
      create(:link, :deleted, account: account)

      create_link(destination_url: "https://example.com/within-the-limit")

      expect(response).to have_http_status(:created)
    end
  end

  # FR-004's other half. FR-019 is the counterweight: this throttles creation
  # and never redirects — see spec/requests/redirect_never_throttled_spec.rb.
  describe "the hourly creation limit" do
    it "refuses past the allowance with a 429" do
      30.times { |n| create_link(destination_url: "https://example.com/#{n}") }

      expect(response).to have_http_status(:created)

      create_link(destination_url: "https://example.com/thirty-one")

      expect(response).to have_http_status(:too_many_requests)
      expect(error_code).to eq("rate_limited")
    end

    it "is per account rather than per origin, so one busy creator does not throttle another" do
      31.times { |n| create_link(destination_url: "https://example.com/#{n}") }

      other = create(:account)
      post "/api/v1/links",
           params: { destination_url: "https://example.com/elsewhere" },
           headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(other)}" },
           as: :json

      expect(response).to have_http_status(:created)
    end
  end

  it "reports a missing destination rather than raising" do
    create_link(name: "no address")

    expect(response).to have_http_status(:unprocessable_content)
    expect(error_code).to eq("parameter_missing")
  end

  it "sets no cookie (FR-015)" do
    create_link(destination_url: "https://example.com/x")

    expect(response.headers["set-cookie"]).to be_nil
  end
end
