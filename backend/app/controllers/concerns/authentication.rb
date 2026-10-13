# frozen_string_literal: true

# Access-token authentication for the JSON API.
#
# Verifying a request touches neither Postgres nor Redis: the access token's
# signature is the whole proof, and `current_account` is loaded lazily so that
# endpoints which only need an account id never load the row at all.
#
# The token arrives one of two ways, and the order below is the priority:
#
#   1. `Authorization: Bearer`, which is what a mobile app or a CLI sends and
#      what research.md D10's first driver exists for.
#   2. The `snip_access` cookie, which is what a browser sends — set by the
#      Next.js BFF on a domain both origins share, and never readable from
#      JavaScript.
#
# Two ways in is a cost, taken deliberately. Holding the browser's token in a
# JavaScript variable meant it died with the page, so every reload spent a
# refresh token to mint another — which is not a security property, it is a
# consequence of where the value was kept, and it made two tabs opening at once
# look like token theft. A cookie the browser stores and attaches is the fix
# for that, and it cannot be read by an XSS the way a variable or localStorage
# can. The header stays because a non-browser client has no cookie jar worth
# the name.
#
# What this does *not* do is accept a cookie as a second kind of credential.
# There is one credential — the signed access token — and this reads it from
# whichever of the two places the client had available. The signature check,
# the claims, and the expiry are identical either way.
#
# `request.cookies` is Rack parsing the header, not `ActionDispatch::Cookies`,
# which is deliberately absent from the stack (config/application.rb). Reading a
# cookie does not grant the ability to set one, so "nothing in this application
# can set a cookie even by accident" survives intact — and with it the
# redirect's structural `no Set-Cookie` guarantee (FR-015, Principle V).
#
# The redirect path never includes this concern at all. It runs in middleware,
# ahead of the router, and reads no credential of any kind (Principle I,
# contracts/redirect.md). In production the short domain is a different
# registrable domain from the one the session cookies are scoped to, so nothing
# is sent there either; in development the two share `localhost` and the cookie
# does arrive, is read by nothing, and cannot be answered with one.
module Authentication
  extend ActiveSupport::Concern

  BEARER_PATTERN = /\ABearer[ ]+(?<token>[^\s]+)\z/i

  # Must match ACCESS_COOKIE in frontend/src/lib/session.ts, which is where it
  # is written. Two string literals that have to agree, so both say so.
  ACCESS_COOKIE = "snip_access"

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

  def cookie_token
    request.cookies[ACCESS_COOKIE].presence
  end

  # Header first. A client that sent both meant the one it had to construct on
  # purpose — a cookie rides along on its own and cannot express intent.
  def access_token = bearer_token || cookie_token

  def require_authentication
    token = access_token

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
