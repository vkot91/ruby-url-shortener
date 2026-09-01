# frozen_string_literal: true

module Api
  module V1
    # FR-001. One sign-in opens one refresh-token family; signing out revokes it.
    class SessionsController < BaseController
      allow_unauthenticated_access only: :create

      # FR-036, both halves. Per origin stops one host working through a
      # password list; per address stops the same list being spread across many
      # origins against one account, which is what credential stuffing actually
      # looks like. Two limits, so two names — Rails keys the counter by the
      # name and would otherwise merge them into one.
      rate_limit to: 10,
                 within: RateLimiting::WINDOW,
                 by: -> { hashed_ip },
                 with: -> { render_indistinguishable_refusal(:too_many_requests) },
                 store: RATE_LIMIT_STORE,
                 name: "sign-in-per-origin",
                 only: :create

      rate_limit to: 5,
                 within: RateLimiting::WINDOW,
                 by: -> { hashed_email(params[:email]) },
                 with: -> { render_indistinguishable_refusal(:too_many_requests) },
                 store: RATE_LIMIT_STORE,
                 name: "sign-in-per-address",
                 only: :create

      def create
        account = Account.authenticate_by(email: params.require(:email), password: params.require(:password))

        return render_indistinguishable_refusal if account.nil? || account.banned?

        render_token_pair(account: account, refresh_token: ::Auth::RefreshTokens.issue(account: account, **token_context))
      end

      def destroy
        record = RefreshToken.find_by(token_digest: RefreshToken.digest(params.require(:refresh_token)))

        # The whole family, not the one token. Signing out means "end this
        # session", and a session is the family that sign-in opened.
        ::Auth::RefreshTokens.revoke_family(record.family_id) if record

        # 204 whether or not the token was found. Reporting "no such token"
        # would let anyone holding a candidate string ask us to confirm it.
        head :no_content
      end

      private

      # FR-036's second sentence, and the reason this is one method rather than
      # a 401 renderer and a 429 renderer.
      #
      # `Account.authenticate_by` runs a bcrypt comparison against a dummy
      # digest when no account matches, so a wrong address and a wrong password
      # cost the same time. That work is wasted if the *body* then differs, and
      # it is wasted just as thoroughly if the throttled response differs — an
      # attacker who can tell "throttled" from "wrong password" has learned that
      # the limiter counting this address has been touched. So the body is
      # byte-identical in both cases and only the status distinguishes them, as
      # contracts/openapi.yaml requires.
      def render_indistinguishable_refusal(status = :unauthorized)
        render_error(code: "invalid_credentials", message: "Invalid email or password", status: status)
      end
    end
  end
end
