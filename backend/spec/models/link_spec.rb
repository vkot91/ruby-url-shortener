# frozen_string_literal: true

require "rails_helper"
RSpec.describe Link do
  describe "scopes" do
    it "excludes soft-deleted links from .active" do
      live = create(:link)
      create(:link, :deleted)

      expect(described_class.active).to contain_exactly(live)
    end

    it "restricts .owned_by to one account's links" do
      mine = create(:link)
      create(:link)

      expect(described_class.owned_by(mine.account)).to contain_exactly(mine)
    end
  end

  # FR-011. Deduplicating destinations would merge two customers' statistics,
  # so nothing in the model or the schema prevents this.
  it "lets two accounts point at the same destination independently" do
    first = create(:link, destination_url: "https://example.com/same")
    second = create(:link, destination_url: "https://example.com/same")

    expect(second.code).not_to eq(first.code)
    expect(second.account).not_to eq(first.account)
  end
end

# == Schema Information
#
# Table name: links
#
#  id              :uuid             not null, primary key
#  banned_at       :datetime
#  clicks_count    :bigint           default(0), not null
#  code            :text             not null
#  deleted_at      :datetime
#  destination_url :text             not null
#  name            :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :uuid             not null
#
# Indexes
#
#  index_links_on_account_id                        (account_id)
#  index_links_on_account_id_and_created_at_active  (account_id,created_at DESC) WHERE (deleted_at IS NULL)
#  index_links_on_code                              (code) UNIQUE
#  index_links_on_destination_url_trgm              (destination_url) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Check Constraints
#
#  links_code_length_check  (length(code) >= 3 AND length(code) <= 32)
#
