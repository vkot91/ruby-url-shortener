# frozen_string_literal: true

class CreateClicks < ActiveRecord::Migration[8.0]
  def change
    # No created_at/updated_at pair here. `occurred_at` is the only time this
    # row has, and it is the redirect's clock, not the insert's: rows arrive up
    # to 30 seconds late in batches (SC-009), so a created_at would record when
    # the flush job ran and quietly invite someone to report clicks by it.
    create_table :clicks do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :link, null: false, foreign_key: true, index: false

      # Captured in the middleware when the redirect is served, not when the
      # batch reaches Postgres — the two are up to 30 seconds apart (SC-009).
      t.datetime :occurred_at, null: false
    end

    add_index :clicks, [ :link_id, :occurred_at ], order: { occurred_at: :desc }

    # There is deliberately no IP column here, and no country, device, referrer,
    # or fingerprint column either (FR-024, Principle V). Absent rather than
    # nullable-and-unused: a column that does not exist cannot be filled in by a
    # careless later commit.
  end
end
