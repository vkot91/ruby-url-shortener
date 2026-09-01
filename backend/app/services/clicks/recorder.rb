# frozen_string_literal: true

module Clicks
  # The naive click path, and the whole of it (T036).
  #
  # Two synchronous writes to Postgres on every redirect — the row and the
  # counter — which is a Principle I violation and is the point. Principle II
  # requires the baseline to be measured before it is optimised, and a baseline
  # that already avoids the bottleneck measures nothing. The waiver is recorded
  # in plan.md, scoped to T035–T044, and expires at T045.
  #
  # It is a service object rather than four lines in the controller so that 3C
  # replaces one file: T053 swaps the body below for a single `LPUSH` onto the
  # Redis buffer, and T055's flush job takes over the two statements. Nothing
  # else has to move.
  module Recorder
    # Both statements bypass the model layer on purpose. The click row has no
    # validations worth running and is written a few thousand times a second;
    # the counter must be incremented atomically, since `link.clicks_count += 1`
    # loses one of two concurrent redirects.
    def self.call(link_id:, occurred_at: Time.current)
      Click.insert!({ link_id: link_id, occurred_at: occurred_at })

      # An atomic increment, not a read-modify-write: two concurrent redirects
      # of the same link must produce two clicks, and `link.clicks_count += 1`
      # would lose one of them.
      Link.update_counters(link_id, clicks_count: 1)
    end
  end
end
