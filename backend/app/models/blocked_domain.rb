# frozen_string_literal: true

class BlockedDomain < ApplicationRecord
  belongs_to :created_by, class_name: "Account", optional: true

  validates :domain, presence: true

  # Adding a domain here does not retroactively ban existing links pointing at
  # it; that is a separate, deliberate admin action (FR-007, FR-031).
end

# == Schema Information
#
# Table name: blocked_domains
#
#  id            :bigint           not null, primary key
#  domain        :citext           not null
#  reason        :text
#  created_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_blocked_domains_on_created_by_id  (created_by_id)
#  index_blocked_domains_on_domain         (domain) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => accounts.id)
#
