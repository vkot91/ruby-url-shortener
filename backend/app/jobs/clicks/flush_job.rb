# frozen_string_literal: true

module Clicks
  # Drains the click buffer into Postgres (T055, D4, FR-020).
  #
  # The redirect path writes one string to a Redis list and stops caring. This
  # job is the other half: every five seconds it takes what has accumulated,
  # writes the rows in one multi-row `INSERT`, and moves every counter in one
  # `UPDATE`. A thousand clicks that cost 3A two thousand synchronous statements
  # cost this two.
  #
  # A plain `Sidekiq::Job` rather than an `ActiveJob`. Active Job's value is
  # portability between backends, and this job is not portable by construction:
  # it is scheduled by sidekiq-scheduler and it exists because the queue is not
  # in Postgres (D9).
  class FlushJob
    include Sidekiq::Job

    # `LPOP key count` is atomic, so two workers cannot take the same entries —
    # which is what allows this to run on a schedule without a lock (D4).
    BATCH_SIZE = 1_000

    # A single run keeps draining until the buffer is empty, because at the
    # throughput this architecture is built for, one batch per five seconds
    # would fall permanently behind: the buffer would grow, not drain. Bounded
    # anyway so that a run cannot outlive its own schedule indefinitely — a
    # backlog beyond this is left for the next run, which is the correct
    # behaviour and a visible one.
    MAX_BATCHES_PER_RUN = 50

    # The retry is off on purpose. `LPOP` has already removed the entries by the
    # time anything can fail, so a retry cannot re-read them; it would only
    # repeat whatever half of the write succeeded. Losing a batch costs seconds
    # of statistics, which the constitution's durability ordering names as
    # acceptable — silently doubling a counter does not.
    sidekiq_options retry: 0

    # Named by the writer rather than re-declared here: two string literals that
    # must agree is a way for a rename to silently orphan a buffer full of
    # clicks.
    BUFFER_KEY = RedirectMiddleware::CLICK_BUFFER_KEY

    def perform
      MAX_BATCHES_PER_RUN.times do
        batch = REDIS.with { |redis| redis.lpop(BUFFER_KEY, BATCH_SIZE) }

        break if batch.blank?

        flush(batch)
      end
    end

    private

    def flush(batch)
      clicks = batch.filter_map { |entry| parse(entry) }

      return if clicks.empty?

      # One transaction so the rows and the counters cannot disagree: a reader
      # of the dashboard never sees a count that no rows support, or rows that
      # the count has not caught up with.
      # Bypassing the model layer is the point rather than a shortcut: a click
      # has no validation worth running, and instantiating a thousand
      # ActiveRecord objects to write a thousand two-column rows would put the
      # cost back where D4 removed it from.
      # rubocop:disable Rails/SkipsModelValidations
      ApplicationRecord.transaction do
        Click.insert_all(clicks)

        increment_counters(clicks)
      end
      # rubocop:enable Rails/SkipsModelValidations
    end

    # `<link_id>:<epoch milliseconds>`, written by RedirectMiddleware. A
    # malformed entry is dropped rather than allowed to fail the batch around
    # it: the only things that can produce one are a truncated write or a
    # future format change, and neither is worth losing a thousand good clicks
    # over.
    def parse(entry)
      link_id, milliseconds = entry.split(":", 2)

      return nil if link_id.blank? || milliseconds.blank?

      { link_id: link_id, occurred_at: Time.zone.at(milliseconds.to_i / 1000.0) }
    end

    # One statement for the whole batch, not one per link. The grouped increment
    # D4 asks for: it reads as an atomic `+ n` per row, so it neither loses a
    # concurrent redirect's click nor needs to know the current value.
    #
    # The aggregation into `deltas` is load-bearing, not tidying. `UPDATE ...
    # FROM` joins each target row once and applies a single matching row from
    # the right-hand side, so feeding it the same link twice would apply one of
    # the two increments and silently drop the other. One row per link is what
    # makes the arithmetic correct.
    #
    # The SQL text is a constant and the batch travels as two bound arrays.
    # Building it by interpolation worked — the id went through `quote` and the
    # count through `to_i` — but it produced a different statement for every
    # batch size, so Postgres re-parsed and re-planned a thousand-tuple `VALUES`
    # list every five seconds and could cache none of it. `unnest` gives one
    # statement shape for every batch. It also leaves nothing for a reader, or
    # for Brakeman, to have to verify: there is no interpolation to audit.
    INCREMENT_SQL = <<~SQL.squish
      UPDATE links
      SET clicks_count = links.clicks_count + deltas.delta
      FROM unnest($1::uuid[], $2::integer[]) AS deltas(id, delta)
      WHERE links.id = deltas.id
    SQL

    UUID_ARRAY = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(ActiveRecord::Type::String.new)
    INTEGER_ARRAY = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(ActiveRecord::Type::Integer.new)

    def increment_counters(clicks)
      deltas = clicks.each_with_object(Hash.new(0)) { |click, counts| counts[click[:link_id]] += 1 }

      binds = [
        ActiveRecord::Relation::QueryAttribute.new("ids", deltas.keys, UUID_ARRAY),
        ActiveRecord::Relation::QueryAttribute.new("deltas", deltas.values, INTEGER_ARRAY)
      ]

      ApplicationRecord.connection.exec_update(INCREMENT_SQL, "Clicks::FlushJob Increment", binds)
    end
  end
end
