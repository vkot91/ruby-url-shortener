# frozen_string_literal: true

# The naive redirect (T035). One Postgres query per request, deliberately.
#
# **Principle I waiver, plan.md**: this controller violates "the redirect path
# is sacred" on purpose. It queries the system of record on every request and
# writes the click synchronously, which is exactly the bottleneck Principle II
# requires be measured before it is removed. Scope: T035–T044. Expiry: T045,
# when RedirectMiddleware (T050) takes this path over and answers from one Redis
# `GETEX` ahead of the router. `REDIRECT_CACHE_ENABLED` keeps this file runnable
# afterwards so the baseline can be re-taken rather than trusted.
#
# What is *not* waived, and holds here exactly as it will in the middleware:
# no cookie on any outcome, `Cache-Control: no-store` on the 302, and no rate
# limiter — a redirect is never throttled by plan or by volume (FR-015, FR-016,
# FR-019).
class RedirectsController < ActionController::API
  # ActionController::API renders JSON and nothing else. The not-found and
  # safety-warning pages are the only HTML this application serves, so the two
  # view modules are pulled in here rather than by moving the whole controller
  # to ActionController::Base — which would drag session and forgery-protection
  # machinery into the one place that must not have it.
  include ActionView::Rendering
  include ActionView::Layouts

  include ErrorHandling

  def show
    link = Link.find_by(code: params[:code])

    return not_found if link.nil? || link.deleted?
    return banned if link.banned? || link.account.banned_at.present?

    Clicks::Recorder.call(link_id: link.id)

    # 302, never 301 (D8, FR-016). A 301 is cached by browsers and
    # intermediaries — sometimes for good — which would make US3's destination
    # edit silently fail for precisely the visitors who clicked before it.
    response.headers["Cache-Control"] = "no-store"

    redirect_to link.destination_url, status: :found, allow_other_host: true
  end

  # FR-017. An explanation of what the service is, not a bare error: this page
  # is the most common first contact an anonymous visitor has with the product
  # (design.md §6.9).
  #
  # Public, and therefore an action as well as the answer `show` gives an
  # unknown code: the root and the catch-all at the foot of config/routes.rb
  # both dispatch straight to it, so a path that could never have been a code
  # gets the same page as a code that does not exist. To a visitor who mistyped
  # a short link the two situations are one situation.
  def not_found
    response.headers["Cache-Control"] = "no-store"

    render "pages/not_found", layout: false, status: :not_found, formats: [ :html ]
  end

  private

  # FR-018. Banned links and the links of banned accounts get the warning page
  # rather than a redirect. The page itself is T084, in Phase 6; until then the
  # decision is made here and the visitor is told plainly, so the resolution
  # order in data-model.md is real from 3A rather than arriving with the
  # moderation UI.
  def banned
    response.headers["Cache-Control"] = "no-store"

    render plain: "This link has been blocked.", status: :forbidden
  end
end
