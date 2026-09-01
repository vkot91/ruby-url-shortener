# frozen_string_literal: true

# `bin/rails db:fixtures:load` reads `test/fixtures` unless told otherwise, and
# this project's fixtures live beside the specs in `spec/fixtures` — the path
# spec/rails_helper.rb already points `config.fixture_paths` at. Setting it here
# rather than expecting `FIXTURES_PATH=spec/fixtures` on the command line means
# the documented command is the whole command.
#
# `enhance` with a prerequisite, not a block: a block runs *after* the task it
# is attached to, and both of these have to happen before a single row moves.
namespace :fixtures do
  task configure: :environment do
    ActiveRecord::Tasks::DatabaseTasks.fixtures_path = Rails.root.join("spec/fixtures").to_s
  end

  # Loading fixtures is not additive. Every table a fixture file names is
  # emptied before it is refilled, so this is a destructive command wearing the
  # name of a helpful one — which is exactly the sort of thing that gets run
  # against production once. The seed file guards itself for the same reason.
  task refuse_in_production: :environment do
    abort "Refusing to load fixtures: they delete every row in the tables they cover." if Rails.env.production?
  end
end

Rake::Task["db:fixtures:load"].enhance([ "fixtures:refuse_in_production", "fixtures:configure" ])
