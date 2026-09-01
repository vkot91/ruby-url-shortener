# frozen_string_literal: true

FactoryBot.define do
  factory :link do
    account
    sequence(:code) { |n| "code#{n.to_s.rjust(3, '0')}" }
    destination_url { "https://example.com/destination" }

    trait :banned do
      banned_at { Time.current }
    end

    trait :deleted do
      deleted_at { Time.current }
    end
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
