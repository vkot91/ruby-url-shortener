# frozen_string_literal: true

module Auth
  # The stateful half. Refresh tokens are the only thing that can extend a
  # session, so they are the only thing that has to be revocable — which is why
  # they are rows and access tokens are not.
  module RefreshTokens
    Error = Class.new(StandardError)
    Invalid = Class.new(Error)
    Reused = Class.new(Error)

    class << self
      def issue(account:, family_id: nil, user_agent: nil, ip_address: nil)
        raw_token = SecureRandom.urlsafe_base64(RefreshToken::TOKEN_BYTES)

        record = RefreshToken.create!(
          account: account,
          token_digest: RefreshToken.digest(raw_token),
          family_id: family_id || SecureRandom.uuid,
          expires_at: RefreshToken::LIFETIME.from_now,
          user_agent: user_agent,
          ip_address: ip_address
        )

        record.token = raw_token

        record
      end

      # Exchanges one token for its successor in the same family.
      #
      # Rotation without reuse detection is rotation theatre: it changes the
      # token but notices nothing when a copy is used behind your back. A token
      # presented after it has already been exchanged means either the client
      # replayed itself or somebody else holds a copy, and there is no way to
      # tell which from here — so the family dies and the human signs in again.
      def rotate(raw_token, user_agent: nil, ip_address: nil)
        raise Invalid if raw_token.blank?

        record = RefreshToken.find_by(token_digest: RefreshToken.digest(raw_token))

        raise Invalid if record.nil?
        raise Invalid if record.revoked?

        if record.used?
          revoke_family(record.family_id)
          raise Reused
        end

        raise Invalid if record.expired?

        RefreshToken.transaction do
          record.update!(used_at: Time.current)

          issue(
            account: record.account,
            family_id: record.family_id,
            user_agent: user_agent,
            ip_address: ip_address
          )
        end
      end

      def revoke_family(family_id)
        # rubocop:disable Rails/SkipsModelValidations
        # One statement on an indexed column. A family is revoked in response to
        # a suspected theft, so this runs on the path where speed matters and
        # where loading the rows to validate them would accomplish nothing.
        RefreshToken.where(family_id: family_id, revoked_at: nil).update_all(revoked_at: Time.current)
        # rubocop:enable Rails/SkipsModelValidations
      end

      def revoke_all_for(account)
        # rubocop:disable Rails/SkipsModelValidations
        RefreshToken.where(account: account, revoked_at: nil).update_all(revoked_at: Time.current)
        # rubocop:enable Rails/SkipsModelValidations
      end
    end
  end
end
