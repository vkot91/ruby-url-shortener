# frozen_string_literal: true

module Auth
  # The stateful half. Refresh tokens are the only thing that can extend a
  # session, so they are the only thing that has to be revocable — which is why
  # they are rows and access tokens are not.
  module RefreshTokens
    Error = Class.new(StandardError)
    Invalid = Class.new(Error)
    Reused = Class.new(Error)

    # How long after a token was spent a second presentation of it is read as
    # the same client retrying rather than as somebody else holding a copy.
    #
    # It exists because "presented twice" has two causes and only one of them
    # is theft. Two browser tabs whose access tokens expire in the same second
    # send the same refresh token within milliseconds of each other; so does a
    # reload that races a poll, or a retry after a response was lost on the
    # way back. Without this window every one of those signed the person out
    # of every tab — a bug that fired on ordinary use and looked exactly like
    # the attack it was meant to catch.
    #
    # Ten seconds is chosen to cover a network round trip and a slow tab
    # waking up, and to be far too short to be worth attacking: an attacker
    # would have to spend a stolen token inside the same ten seconds the
    # legitimate client spent it, having stolen it before that. Outside the
    # window — which is where a copy taken from a log, a backup, or a
    # proxy actually gets used — detection is unchanged.
    GRACE = 10.seconds

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
      # presented long after it has already been exchanged means somebody holds
      # a copy, and there is no way to tell whose from here — so the family dies
      # and the human signs in again.
      def rotate(raw_token, user_agent: nil, ip_address: nil)
        raise Invalid if raw_token.blank?

        record = RefreshToken.find_by(token_digest: RefreshToken.digest(raw_token))

        raise Invalid if record.nil?
        raise Invalid if record.revoked?

        if record.used?
          # Inside the window this issues a *second* successor in the family
          # rather than handing back the first, and it does so because it
          # cannot hand back the first: only the digest is stored, so the raw
          # string is unrecoverable by construction (which is the property that
          # makes the table safe to hold). The cost is bounded and stated: for
          # up to ten seconds a family can carry two live tokens.
          raise Reused unless within_grace?(record)

          return issue(
            account: record.account,
            family_id: record.family_id,
            user_agent: user_agent,
            ip_address: ip_address
          )
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

      # `revoke_family` runs before the raise, so a genuine reuse still ends the
      # session on the spot — the grace check only decides which of the two
      # branches above is taken.
      def within_grace?(record)
        return true if record.used_at.present? && record.used_at > GRACE.ago

        revoke_family(record.family_id)

        false
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
