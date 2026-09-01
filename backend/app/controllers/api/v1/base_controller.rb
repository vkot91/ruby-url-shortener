# frozen_string_literal: true

module Api
  module V1
    # Everything under /api/v1. Authenticated by default: an endpoint that
    # should be open says so with `allow_unauthenticated_access`, which means a
    # new controller added in a hurry is closed rather than open.
    # Note the `::Auth::` prefixes in the controllers below this one. The
    # refresh endpoint's path (contracts/openapi.yaml `/auth/refresh`) gives
    # this namespace a nested `Api::V1::Auth` module, which shadows the
    # top-level `Auth` holding the token services — so every reference to them
    # from inside `Api::V1` has to say which one it means.
    class BaseController < ApplicationController
      include Authentication
      include RateLimiting
      include TokenIssuing
    end
  end
end
