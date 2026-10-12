# frozen_string_literal: true

require "rails_helper"

# FR-002. The list and the single fetch are the two endpoints that could hand
# one account another account's rows, so both are asserted here rather than only
# the list — a `show` that forgot the ownership scope would leak one link at a
# time, quietly, and a list-only spec would go on passing.
RSpec.describe "link isolation between accounts", type: :request do
  let(:alice) { create(:account) }
  let(:bob) { create(:account) }

  let!(:alices_link) { create(:link, account: alice, destination_url: "https://example.com/alice") }
  let!(:bobs_link) { create(:link, account: bob, destination_url: "https://example.com/bob") }

  def as(account, path)
    get path, headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" }, as: :json
  end

  describe "GET /api/v1/links" do
    it "returns only the caller's own links" do
      as(bob, "/api/v1/links")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["links"].pluck("id")).to contain_exactly(bobs_link.id)
    end

    it "counts only the caller's own links, so the pagination total cannot leak a rival's volume" do
      create_list(:link, 3, account: alice)

      as(bob, "/api/v1/links")

      expect(response.parsed_body.dig("pagination", "total")).to eq(1)
    end

    it "returns the Link schema from contracts/openapi.yaml for each row" do
      as(bob, "/api/v1/links")

      expect(response.parsed_body["links"].first.keys)
        .to match_array(%w[id code short_url destination_url name clicks_count created_at])
    end

    it "omits the fields that belong to AdminLink, not to Link (FR-034, design.md P6)" do
      as(bob, "/api/v1/links")

      expect(response.parsed_body["links"].first.keys).not_to include("account_id", "banned_at", "deleted_at")
    end

    it "hides a soft-deleted link from its own creator, while the row survives (FR-028)" do
      bobs_link.update!(deleted_at: Time.current)

      as(bob, "/api/v1/links")

      expect(response.parsed_body["links"]).to be_empty
      expect(Link.find(bobs_link.id)).to be_present
    end

    it "requires authentication" do
      get "/api/v1/links", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/links/:id" do
    it "returns the caller's own link" do
      as(bob, "/api/v1/links/#{bobs_link.id}")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(bobs_link.id)
    end

    # The point of FR-002's "indistinguishable": 403 would confirm that the id
    # names a real link, which is exactly the fact the caller is not entitled to.
    it "answers 404 for another account's link, not 403" do
      as(bob, "/api/v1/links/#{alices_link.id}")

      expect(response).to have_http_status(:not_found)
    end

    it "answers a missing id with a byte-identical body, so the two cases cannot be told apart" do
      as(bob, "/api/v1/links/#{alices_link.id}")
      another_accounts = response.body

      as(bob, "/api/v1/links/#{SecureRandom.uuid}")

      expect(response.body).to eq(another_accounts)
    end

    it "answers 404 for a soft-deleted link of the caller's own" do
      bobs_link.update!(deleted_at: Time.current)

      as(bob, "/api/v1/links/#{bobs_link.id}")

      expect(response).to have_http_status(:not_found)
    end
  end
end
