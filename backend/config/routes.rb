# frozen_string_literal: true

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no
  # exceptions, otherwise 500. Used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Singular paths, plural names: one registration is created, one session
      # is opened, and neither is a collection anybody lists
      # (contracts/openapi.yaml).
      post "registrations" => "registrations#create"
      post "sessions" => "sessions#create"
      delete "sessions" => "sessions#destroy"

      namespace :auth do
        post "refresh" => "refresh#create"
      end

      # Only `create` in 3A. `index` and `show` arrive with US2 (T063, T106),
      # `update` and `destroy` with US3 (T075, T077) — listed as they land
      # rather than drawn now and answering 404 from a missing action.
      resources :links, only: :create

      namespace :admin do
        # FR-003 surface. Same reasoning: `/admin` is claimed now, not later.
      end
    end

    # Anything under /api that no route above claimed. Without this the HTML
    # catch-all at the foot of this file would answer an API client's typo with
    # a page about short links; a client that parses JSON deserves JSON, and
    # `not_found` is already one of the codes contracts/openapi.yaml defines.
    match "*unmatched", to: "errors#not_found", via: :all
  end

  # The public redirect surface (contracts/redirect.md). Last, so every segment
  # claimed above wins the match — the ordering FR-012 depends on.
  #
  # The constraint is the same `[A-Za-z0-9]{3,32}` the contract states: anything
  # else is not a code and falls through to a 404 from the router rather than
  # reaching a controller that would look it up.
  #
  # In Phase 3C this route is superseded by RedirectMiddleware (T050), which
  # answers ahead of the router entirely. It stays drawn, because
  # `REDIRECT_CACHE_ENABLED` false must keep the naive path runnable — that is
  # the whole mechanism by which the baseline can be re-measured later
  # (Principle II).
  get "/:code" => "redirects#show", constraints: { code: /[A-Za-z0-9]{3,32}/ }, as: :redirect

  # Everything else on this domain, including the bare root.
  #
  # A path that cannot be a code is still a visitor who was trying to follow
  # somebody's link — a truncated `/ab`, a mistyped `/not-a-code`, a bare
  # `snp.to` — and FR-017 owes all of them the page that explains what the
  # service is. Without these two lines they get Rails' default 404, which on
  # an application with no `public/404.html` is an empty text/plain body.
  #
  # A route rather than `config.exceptions_app`, which is the other way to do
  # this. exceptions_app only runs when `consider_all_requests_local` is false,
  # so the branded page would be invisible in development and in test — the two
  # environments where anyone would look at it before production. A 404 here is
  # an ordinary response this domain owes its visitors, not an exception.
  root "redirects#not_found"

  match "*unmatched", to: "redirects#not_found", via: :all

  # The segments this file claims are enumerated in
  # config/initializers/reserved_paths.rb and refused as codes at creation
  # (FR-012) — a code the router would swallow is a code that never redirects.
  # Adding a top-level route here means adding its segment there.
end
