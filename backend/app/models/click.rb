# frozen_string_literal: true

# Written only by Clicks::FlushJob, in batches, never by a web request (D4,
# Principle I). The row holds a link and a timestamp and nothing that could
# identify the visitor (FR-024, Principle V).
class Click < ApplicationRecord
  belongs_to :link

  validates :occurred_at, presence: true
end

# == Schema Information
#
# Table name: clicks
#
#  id          :uuid             not null, primary key
#  occurred_at :datetime         not null
#  link_id     :uuid             not null
#
# Indexes
#
#  index_clicks_on_link_id_and_occurred_at  (link_id,occurred_at DESC)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
