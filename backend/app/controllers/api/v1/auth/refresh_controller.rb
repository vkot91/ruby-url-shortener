# frozen_string_literal: true

module Api
  module V1
    module Auth
      # research.md D10. The only endpoint that can extend a session, and
      # therefore the only one that has to be revocable.
      #
      # Unauthenticated on purpose: a client reaches here precisely because its
      # access token has expired, and requiring a live one would make refresh
      # impossible exactly when it is needed. The refresh token is the credential.
      class RefreshController < BaseController
        allow_unauthenticated_access

        # FR-036. Generous compared with sign-in: a legitimate client refreshes
        # roughly four times an hour, but many of them sit behind one NAT
        # address, and throttling refresh is throttling people who are already
        # signed in.
        rate_limit to: 60,
                   within: RateLimiting::WINDOW,
                   by: -> { hashed_ip },
                   with: -> { render_rate_limited },
                   store: RATE_LIMIT_STORE

        def create
          successor = ::Auth::RefreshTokens.rotate(params.require(:refresh_token), **token_context)

          render_token_pair(account: successor.account, refresh_token: successor)
        rescue ::Auth::RefreshTokens::Reused
          # The family has already been revoked by the time this is rendered.
          # The code is distinct from the one below because the situations are:
          # this one means somebody presented a token that had already been
          # spent, and the client cannot know whether that somebody was itself.
          render_error(
            code: "token_reuse_detected",
            message: "This session has been ended for safety. Sign in again.",
            status: :unauthorized
          )
        rescue ::Auth::RefreshTokens::Invalid
          render_error(code: "invalid_refresh_token", message: "Sign in required", status: :unauthorized)
        end
      end
    end
  end
end
