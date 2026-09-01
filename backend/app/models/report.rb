# frozen_string_literal: true

class Report < ApplicationRecord
  STATUSES = %w[pending actioned dismissed].freeze

  belongs_to :link
  belongs_to :reviewed_by, class_name: "Account", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :reason, length: { maximum: 500 }, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :oldest_first, -> { order(created_at: :asc) }
end

# == Schema Information
#
# Table name: reports
#
#  id             :uuid             not null, primary key
#  reason         :text
#  reviewed_at    :datetime
#  status         :text             default("pending"), not null
#  created_at     :datetime         not null
#  link_id        :uuid             not null
#  reviewed_by_id :uuid
#
# Indexes
#
#  index_reports_on_link_id                (link_id)
#  index_reports_on_reviewed_by_id         (reviewed_by_id)
#  index_reports_on_status_and_created_at  (status,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (reviewed_by_id => accounts.id)
#
# Check Constraints
#
#  reports_status_check  (status = ANY (ARRAY['pending'::text, 'actioned'::text, 'dismissed'::text]))
#
