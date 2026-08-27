# frozen_string_literal: true

# Top-level path segments that the Rails router claims before
# RedirectMiddleware's `/:code` pattern can apply, plus the segments the
# frontend owns on the app domain. Link creation refuses them as codes (FR-012).
#
# This lives in an initializer rather than in config/routes.rb because
# config/routes.rb is loaded lazily: a service object asking for the list in a
# unit test that never issues a request would otherwise get nothing back, and
# would silently accept `api` as a code. See the note at the foot of
# config/routes.rb — adding a top-level route means adding its segment here.
#
# Comparison is case-insensitive at the point of use: codes are [A-Za-z0-9], so
# `Admin` collides with the same route that `admin` does.
Rails.application.config.x.reserved_codes = %w[
  admin
  api
  assets
  favicon
  login
  logout
  packs
  robots
  settings
  signup
  sitemap
  static
  up
].freeze
