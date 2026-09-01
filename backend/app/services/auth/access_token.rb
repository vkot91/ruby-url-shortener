# frozen_string_literal: true

module Auth
  # The stateless half of authentication. A valid signature is the whole proof:
  # verifying one touches no database and no cache, which is the property the
  # short lifetime below pays for.
  module AccessToken
    ALGORITHM = "HS256"

    # The blast radius of every stolen access token, and the delay before an
    # account ban or a role change takes effect. Shortening it costs refresh
    # round trips; lengthening it widens both windows. Fifteen minutes is the
    # documented trade, not an accident — see research.md D10.
    LIFETIME = 15.minutes

    Claims = Data.define(:account_id, :role, :jti)

    Error = Class.new(StandardError)
    Expired = Class.new(Error)
    Invalid = Class.new(Error)

    class << self
      def encode(account)
        issued_at = Time.current

        payload = {
          sub: account.id.to_s,
          role: account.role,
          jti: SecureRandom.uuid,
          iat: issued_at.to_i,
          exp: (issued_at + LIFETIME).to_i
        }

        JWT.encode(payload, secret, ALGORITHM)
      end

      def decode(raw_token)
        # `algorithm:` pins verification to HS256. Without it the library would
        # honour whatever the token's own header asks for, which is how `alg:
        # none` and HS/RS confusion attacks get in.
        payload, = JWT.decode(
          raw_token,
          secret,
          true,
          algorithm: ALGORITHM,
          verify_expiration: true,
          required_claims: %w[sub role exp jti]
        )

        # `sub` is the account's UUID, carried as the string it already is. It
        # is deliberately not cast or validated here: a malformed value finds no
        # account, and the lookup is the check. Coercing it would only move the
        # same rejection earlier and give a caller a second failure mode to
        # handle.
        Claims.new(account_id: payload["sub"], role: payload["role"], jti: payload["jti"])
      rescue JWT::ExpiredSignature
        raise Expired
      rescue JWT::DecodeError, ArgumentError, TypeError
        raise Invalid
      end

      private

      # Derived from secret_key_base rather than carried as its own environment
      # variable: one secret to configure, one secret to rotate. The generator
      # Rails hands back caches its derivations, so this is not a PBKDF2 run per
      # request.
      def secret
        @secret ||= Rails.application.key_generator.generate_key("auth/access_token", 32)
      end
    end
  end
end
