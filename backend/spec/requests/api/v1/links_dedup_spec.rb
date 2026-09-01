# frozen_string_literal: true

require "rails_helper"

# FR-011. The tempting optimisation is to notice that two creators shortened the
# same address and hand them the same code. It is the wrong optimisation: it
# merges two customers' statistics, and it means either of them deleting their
# link breaks the other's poster.
#
# There is deliberately no unique index on `destination_url` for the same
# reason (data-model.md), so this spec is the thing standing between that index
# and a future commit that thinks it looks like an oversight.
RSpec.describe "Two accounts shortening the same destination", type: :request do
  let(:destination) { "https://example.com/the-same-campaign" }
  let(:first) { create(:account) }
  let(:second) { create(:account) }

  def shorten(account)
    post "/api/v1/links",
         params: { destination_url: destination },
         headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" },
         as: :json

    response.parsed_body
  end

  it "gives each of them their own code" do
    expect(shorten(first)["code"]).not_to eq(shorten(second)["code"])
  end

  it "gives each of them their own link owned by themselves" do
    first_link = Link.find(shorten(first)["id"])
    second_link = Link.find(shorten(second)["id"])

    expect(first_link.account).to eq(first)
    expect(second_link.account).to eq(second)
    expect(first_link.destination_url).to eq(second_link.destination_url)
  end

  it "counts their clicks independently" do
    first_code = shorten(first)["code"]
    second_code = shorten(second)["code"]

    3.times { get "/#{first_code}" }
    get "/#{second_code}"

    expect(Link.find_by(code: first_code).clicks_count).to eq(3)
    expect(Link.find_by(code: second_code).clicks_count).to eq(1)
  end

  it "leaves one working when the other is deleted" do
    first_code = shorten(first)["code"]
    second_code = shorten(second)["code"]

    Link.find_by(code: first_code).update!(deleted_at: Time.current)

    get "/#{first_code}"
    expect(response).to have_http_status(:not_found)

    get "/#{second_code}"
    expect(response).to have_http_status(:found)
  end

  # The same account shortening the same address twice is also two links. It is
  # not our business to decide they made a mistake — two posters can carry two
  # codes for one page precisely so their performance can be compared.
  it "does not merge them for one account either" do
    expect(shorten(first)["code"]).not_to eq(shorten(first)["code"])
    expect(first.links.count).to eq(2)
  end
end
