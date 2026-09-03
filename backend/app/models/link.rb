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

  # T058, Principle IV, D2. The cached copy dies with the write that made it
  # wrong, in the same operation and before the caller is told the write
  # happened.
  #
  # `after_commit`, not `after_save`: deleting the key while the transaction is
  # still open lets a concurrent reader miss, read the *old* committed row, and
  # repopulate the cache with a value that is stale for the next 24 hours. The
  # window after the commit has no such reader.
  #
  # Redis errors are deliberately not rescued for an edit. Everywhere else in
  # this application an unavailable cache degrades the service; here it would
  # mean acknowledging an edit while continuing to send visitors to the old
  # destination, which is the failure Principle IV exists to forbid. Better a
  # failed edit the creator can retry than a successful one that does nothing.
  after_commit :invalidate_cache, on: %i[update destroy]

  # A create clears the cache too, because a code can be cached before it
  # exists: somebody probing `/aB3xY9q` leaves a `__404__` sentinel behind (D7),
  # and without this a link created seconds later would answer 404 for a minute.
  #
  # This one *is* rescued, and the asymmetry is the point. The stale fact here
  # is an absence that expires by itself in sixty seconds (NegativeCache::TTL),
  # so the worst case is a minute of a new link not resolving — while raising
  # would mean nobody can create a link at all whenever Redis blinks. An edit
  # has no such expiry: its stale value lives for a day.
  after_commit :clear_cached_absence, on: :create

  def banned?
    banned_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  private

  def invalidate_cache
    Cache::LinkCache.delete(code)
  end

  def clear_cached_absence
    invalidate_cache
  rescue *REDIS_UNAVAILABLE_ERRORS => error
    Rails.logger.warn(JSON.generate(event: "link_cache_invalidation_skipped", code: code, error: error.class.name))
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
