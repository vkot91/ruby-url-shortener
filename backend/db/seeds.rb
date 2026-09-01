# frozen_string_literal: true

# Run automatically by `db:prepare` when the database is created, and re-runnable
# at any time with `bin/rails db:seed`.
#
# The data itself lives in spec/fixtures rather than here, so there is one
# description of the development dataset instead of two that drift. This file is
# the boot-time entry point into it; `bin/rails db:fixtures:load` is the manual
# one, and both put the database in the same state.
#
# Note what that means: seeding is no longer additive. Every table the fixtures
# cover is emptied and refilled, so a `db:seed` discards whatever you created by
# hand since the last one. That is the trade for determinism — the dataset is
# identical on every machine and after every `db:reset`, which is the whole
# reason the Bruno collection can sign in with one request.
#
# Guarded rather than merely discouraged: these accounts have published
# passwords, and a seed file is exactly the sort of thing that gets run against
# production once.
if Rails.env.production?
  warn "Skipping fixtures: they carry published credentials and delete every row in the tables they cover."
else
  fixtures_path = Rails.root.join("spec/fixtures")
  fixture_names = fixtures_path.glob("*.yml").map { |file| file.basename(".yml").to_s }

  ActiveRecord::FixtureSet.create_fixtures(fixtures_path, fixture_names)

  Rails.logger.info { "Seeded #{fixture_names.size} fixture sets: #{fixture_names.sort.join(', ')}" }
end
