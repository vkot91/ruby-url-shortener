# frozen_string_literal: true

module Api
  # The JSON end of the routing table, for any path under /api that no route
  # claimed. It exists so that the HTML catch-all serving the short domain never
  # answers an API client — a page about short links is not something a client
  # expecting `{ "error": { "code" } }` can do anything with.
  class ErrorsController < ActionController::API
    include ErrorHandling

    # No authentication, deliberately. Demanding a token before admitting that a
    # path does not exist would report a typo as `unauthenticated`, which sends
    # whoever made it looking at their credentials.
    def not_found
      render_not_found
    end
  end
end
