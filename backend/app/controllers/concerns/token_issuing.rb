# frozen_string_literal: true

# The `TokenPair` response body, in one place.
#
# Three endpoints hand out a pair — registration, sign-in, and refresh — and the
# shape is a contract (contracts/openapi.yaml `TokenPair`). `expires_in` is
# derived from the lifetime constant rather than written as 900, so shortening
# the access-token window is one edit and not a bug report from a client that
# refreshed on the old schedule.
module TokenIssuing
  extend ActiveSupport::Concern

  private

  def render_token_pair(account:, refresh_token:)
    render json: {
      access_token: Auth::AccessToken.encode(account),
      refresh_token: refresh_token.token,
      expires_in: Auth::AccessToken::LIFETIME.to_i
    }, status: :created
  end

  # The account holder's own user agent and address, recorded against the
  # refresh token so a person can later be shown where their sessions are. This
  # is not the redirect path and Principle V does not reach it — the data-model
  # note on `refresh_tokens` says so explicitly.
  def token_context
    { user_agent: request.user_agent, ip_address: request.remote_ip }
  end
end
