# frozen_string_literal: true

# Which origin the browser is allowed to send its access cookie to.
#
# The dashboard runs on its own origin and calls this API directly for
# everything that is not authentication (research.md D10, D10a). Without this
# every `/api/v1/*` request from the browser is refused before it is sent.
#
# Two deliberate narrowings, each of which `origins "*"` would give away, and
# one thing that is opened on purpose:
#
#   - **One origin, named.** `APP_URL` is already required configuration and is
#     already the address the two server-rendered pages link to, so there is one
#     place to change when the dashboard moves. A wildcard would let any page on
#     the internet read this API with a token it had somehow obtained.
#   - **`/api/*` only.** The redirect surface is not an XHR target and never
#     will be: a visitor arrives by navigating, which the same-origin policy
#     does not govern at all.
#   - **Credentials on.** The browser's access token is an httpOnly cookie the
#     BFF sets (research.md D10a), and it is not attached to a cross-origin
#     fetch unless this API says it may be. That is safe only alongside the one
#     named origin above; the reasoning sits next to the flag itself in
#     config/application.rb. Rails still sets no cookie anywhere.
#
# The stack position matters as much as the rules. This goes *after*
# RedirectMiddleware, not at position 0 where the generated template puts it,
# so a cached redirect never enters this middleware at all (Principle I). The
# insertion is in config/application.rb, next to the redirect middleware's own,
# because the two are an ordering decision and reading half of one is worse than
# reading neither.
Rails.application.config.x.cors_origins = [ Rails.application.config.x.app_url ].freeze
