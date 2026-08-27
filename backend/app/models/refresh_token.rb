# frozen_string_literal: true

class RefreshToken < ApplicationRecord
  TOKEN_BYTES = 32
  LIFETIME = 30.days

  belongs_to :account

  # Set only on the token returned by Auth::RefreshTokens.issue, and never read
  # back from the database — the raw value exists in the caller's hands and
  # nowhere else.
  attr_accessor :token

  # SHA-256 rather than bcrypt, deliberately. A refresh token is looked up *by*
  # its digest, which rules out a per-row salt, and bcrypt's deliberate slowness
  # protects human-chosen passwords — it buys nothing against 256 bits from a
  # CSPRNG.
  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def revoked?
    revoked_at.present?
  end

  def used?
    used_at.present?
  end

  def expired?
    expires_at <= Time.current
  end
end

# == Schema Information
#
# Table name: refresh_tokens
#
#  id           :bigint           not null, primary key
#  expires_at   :datetime         not null
#  ip_address   :text
#  revoked_at   :datetime
#  token_digest :text             not null
#  used_at      :datetime
#  user_agent   :text
#  created_at   :datetime         not null
#  account_id   :bigint           not null
#  family_id    :uuid             not null
#
# Indexes
#
#  index_refresh_tokens_on_account_id    (account_id)
#  index_refresh_tokens_on_family_id     (family_id)
#  index_refresh_tokens_on_token_digest  (token_digest) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
