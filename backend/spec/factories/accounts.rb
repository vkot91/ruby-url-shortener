# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:email) { |n| "creator#{n}@example.com" }
    password { "a-sufficiently-long-passphrase" }

    trait :admin do
      role { "admin" }
    end

    trait :banned do
      banned_at { Time.current }
    end
  end
end

# == Schema Information
#
# Table name: accounts
#
#  id              :bigint           not null, primary key
#  banned_at       :datetime
#  email           :citext           not null
#  password_digest :text             not null
#  plan            :text             default("free"), not null
#  role            :text             default("creator"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_accounts_on_email  (email) UNIQUE
#
# Check Constraints
#
#  accounts_plan_check  (plan = 'free'::text)
#  accounts_role_check  (role = ANY (ARRAY['creator'::text, 'admin'::text]))
#
