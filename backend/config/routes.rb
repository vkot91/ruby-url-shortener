# frozen_string_literal: true

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no
  # exceptions, otherwise 500. Used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Endpoints arrive with the user stories in Phases 3-6. The namespace is
      # declared from this commit so that `/api` is a claimed top-level segment
      # before the first controller exists, rather than becoming one later and
      # colliding with codes already issued.
      namespace :admin do
        # FR-003 surface. Same reasoning: `/admin` is claimed now, not later.
      end
    end
  end

  # Everything not matched above falls through to RedirectMiddleware's `/:code`
  # pattern in Phase 3C. The segments this file claims are enumerated in
  # config/initializers/reserved_paths.rb and refused as codes at creation
  # (FR-012) — a code the router would swallow is a code that never redirects.
  # Adding a top-level route here means adding its segment there.
end
