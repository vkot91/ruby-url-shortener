# frozen_string_literal: true

require "rails_helper"

# FR-023 and the `Pagination` schema in contracts/openapi.yaml. Ordering and
# page arithmetic are the parts of the list a client cannot verify for itself:
# it sees 25 rows either way and has no way to tell a correct page 2 from one
# that skipped a link.
RSpec.describe "GET /api/v1/links pagination", type: :request do
  let(:account) { create(:account) }

  # Query string, not `as: :json`. The two are not interchangeable on a GET:
  # the JSON encoder puts `params` in the request *body*, which is not where
  # page and per_page arrive from a browser and not where this endpoint reads
  # them.
  def list(query = {})
    get "/api/v1/links",
        params: query,
        headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" }
  end

  def returned_codes = response.parsed_body["links"].pluck("code")

  # Created at distinct times, because "newest first" is untestable against rows
  # that share a timestamp — and the tie-break on id exists precisely so that a
  # page boundary landing inside such a group cannot drop or repeat a link.
  def create_links(count)
    Array.new(count) do |index|
      travel_to(index.hours.ago) { create(:link, account: account, code: "link#{index.to_s.rjust(3, '0')}") }
    end
  end

  it "returns the newest link first (design.md §6.3)" do
    create_links(3)

    list

    expect(returned_codes.first).to eq("link000")
  end

  it "defaults to 25 per page" do
    create_links(30)

    list

    expect(response.parsed_body["links"].size).to eq(25)
    expect(response.parsed_body["pagination"]).to include("page" => 1, "per_page" => 25, "total" => 30)
  end

  it "continues from where page 1 stopped, with no link dropped and none repeated" do
    create_links(30)

    list(per_page: 10, page: 1)
    first_page = returned_codes

    list(per_page: 10, page: 2)
    second_page = returned_codes

    expect(second_page).to eq(%w[link010 link011 link012 link013 link014 link015 link016 link017 link018 link019])
    expect(first_page & second_page).to be_empty
  end

  it "returns an empty page rather than an error past the end" do
    create_links(3)

    list(page: 9)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["links"]).to be_empty
    expect(response.parsed_body.dig("pagination", "total")).to eq(3)
  end

  # A clamp, not a validation: the request is unambiguous, and answering it with
  # the largest page the server will send plus a `pagination` block saying so is
  # more useful than a 422 the client has to special-case.
  it "clamps an oversized per_page to the contract's maximum" do
    create_links(2)

    list(per_page: 500)

    expect(response.parsed_body.dig("pagination", "per_page")).to eq(Api::V1::LinksController::MAX_PER_PAGE)
  end

  it "treats a nonsensical page or per_page as the first page at the default size" do
    create_links(2)

    list(page: 0, per_page: "abc")

    expect(response.parsed_body["pagination"]).to include("page" => 1, "per_page" => 25)
    expect(response.parsed_body["links"].size).to eq(2)
  end
end
