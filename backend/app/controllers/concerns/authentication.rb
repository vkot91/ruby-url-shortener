# frozen_string_literal: true

# Bearer-token authentication for the JSON API.
#
# Verifying a request touches neither Postgres nor Redis: the access token's
# signature is the whole proof, and `current_account` is loaded lazily so that
# endpoints which only need an account id never load the row at all.
#
# The redirect path never includes this concern. It runs in middleware, ahead of
# the router, and reads no credential of any kind (Principle I,
# contracts/redirect.md).
module Authentication
  extend ActiveSupport::Concern

  BEARER_PATTERN = /\ABearer[ ]+(?<token>[^\s]+)\z/i

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def bearer_token
    BEARER_PATTERN.match(request.headers["Authorization"].to_s)&.[](:token)
  end

  def require_authentication
    token = bearer_token

    return render_unauthenticated if token.blank?

    @access_claims = Auth::AccessToken.decode(token)
  rescue Auth::AccessToken::Expired
    # Deliberately distinct from `unauthenticated`. An expired token means "go
    # refresh and retry"; anything else means "sign in again". A client that
    # cannot tell them apart either bounces the user out of a working session or
    # retries forever against a token that will never work.
    render_error(code: "token_expired", message: "Access token expired", status: :unauthorized)
  rescue Auth::AccessToken::Invalid
    render_unauthenticated
  end

  def render_unauthenticated
    render_error(code: "unauthenticated", message: "Sign in required", status: :unauthorized)
  end

  def current_account_id
    @access_claims&.account_id
  end

  # Read from the token, not from the row. A role change therefore takes effect
  # at the next refresh rather than the next request — the same bounded window
  # an account ban has, and documented in research.md D10 for the same reason.
  def current_account_role
    @access_claims&.role
  end

  def current_account_admin?
    current_account_role == "admin"
  end

  # The row, for the endpoints that genuinely need it. Everything that can work
  # from `current_account_id` alone should, since that is what keeps an
  # authenticated request free of database work.
  def current_account
    return nil if current_account_id.nil?

    @current_account ||= Account.find(current_account_id)
  end
end
