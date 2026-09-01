# frozen_string_literal: true

class Account < ApplicationRecord
  ROLES = %w[creator admin].freeze
  PLANS = %w[free].freeze

  # FR-004. Counted over links that have not been soft-deleted.
  FREE_LINK_LIMIT = 50

  has_secure_password

  has_many :refresh_tokens, dependent: :delete_all
  has_many :links, dependent: :restrict_with_exception

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Length only, and a long one — contracts/openapi.yaml sets the minimum at 12.
  # No composition rules: a 12-character passphrase beats an 8-character one
  # with a digit bolted on, and rules that forbid the former are why people
  # write the latter down. `allow_nil` because the digest is what persists, so
  # every read of an existing row would otherwise have to carry the password.
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :role, inclusion: { in: ROLES }
  validates :plan, inclusion: { in: PLANS }

  # Principle IV's reasoning applied to credentials rather than to cache: the
  # revocation belongs to the write that causes it, not to whichever controller
  # remembers to call it. A ban therefore ends every session of that account
  # however the ban was applied — admin endpoint, console, or rake task.
  after_update_commit :revoke_refresh_tokens, if: :saved_change_to_banned_at?

  # There is deliberately no `uniqueness: true` on email. A validation would be
  # a check-then-write with a window in it; the unique index has no window, so
  # registration attempts the insert and translates the violation (Principle III).

  def admin?
    role == "admin"
  end

  def creator?
    role == "creator"
  end

  def banned?
    banned_at.present?
  end

  private

  # Unbanning does not resurrect the old tokens; the account signs in again.
  def revoke_refresh_tokens
    Auth::RefreshTokens.revoke_all_for(self)
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
