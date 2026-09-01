# frozen_string_literal: true

module Api
  module V1
    # FR-001. Registration opens the account's first refresh-token family, so a
    # new account is signed in without a second round trip.
    class RegistrationsController < BaseController
      allow_unauthenticated_access

      # FR-036. Per origin: an account is free, so without this one host can
      # mint them faster than a moderator can look at them.
      rate_limit to: 10,
                 within: RateLimiting::WINDOW,
                 by: -> { hashed_ip },
                 with: -> { render_rate_limited },
                 store: RATE_LIMIT_STORE

      def create
        account = Account.create!(email: params.require(:email), password: params.require(:password))

        render_token_pair(account: account, refresh_token: ::Auth::RefreshTokens.issue(account: account, **token_context))
      rescue ActiveRecord::RecordNotUnique
        # There is no uniqueness validation to catch this first, deliberately —
        # a validation is a check-then-write with a window in it, and the unique
        # index has no window (Principle III). The violation is translated here
        # into the same envelope a validation failure would have produced.
        render_error(
          code: "validation_failed",
          message: "Email has already been taken",
          status: :unprocessable_content,
          details: { email: [ "has already been taken" ] }
        )
      end
    end
  end
end
