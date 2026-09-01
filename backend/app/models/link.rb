# frozen_string_literal: true

class Link < ApplicationRecord
  CODE_LENGTH_RANGE = (3..32)

  belongs_to :account

  has_many :clicks, dependent: :delete_all
  has_many :reports, dependent: :delete_all

  # Backs the dashboard list and the redirect's first resolution step. Matches
  # the partial index on (account_id, created_at DESC) WHERE deleted_at IS NULL.
  scope :active, -> { where(deleted_at: nil) }
  scope :owned_by, ->(account) { where(account: account) }

  validates :code, presence: true, length: { in: CODE_LENGTH_RANGE }
  validates :destination_url, presence: true

  # No uniqueness validation on `code`, and none on `destination_url` either.
  # The first is the unique index's job (Principle III, D3); the second must not
  # exist at all, since two accounts shortening the same destination are
  # entitled to two codes and two independent counters (FR-011).

  def banned?
    banned_at.present?
  end

  def deleted?
    deleted_at.present?
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
