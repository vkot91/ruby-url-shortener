# frozen_string_literal: true

module Clicks
  # The naive click path, and the whole of it (T036).
  #
  # Two synchronous writes to Postgres on every redirect — the row and the
  # counter — which is a Principle I violation and is the point. Principle II
  # requires the baseline to be measured before it is optimised, and a baseline
  # that already avoids the bottleneck measures nothing. The waiver is recorded
  # in plan.md and scoped to T035–T044.
  #
  # 3C did not replace this; it routed around it. RedirectMiddleware buffers the
  # click with one `LPUSH` (T053) and Clicks::FlushJob writes the two statements
  # below in batches of a thousand (T055). What is left here is what the naive
  # path still does, and therefore what a re-run of the baseline still measures.
  module Recorder
    # Both statements bypass the model layer on purpose. The click row has no
    # validations worth running and is written a few thousand times a second;
    # the counter must be incremented atomically, since `link.clicks_count += 1`
    # loses one of two concurrent redirects.
    # rubocop:disable Rails/SkipsModelValidations
    def self.call(link_id:, occurred_at: Time.current)
      Click.insert!({ link_id: link_id, occurred_at: occurred_at })

      # An atomic increment, not a read-modify-write: two concurrent redirects
      # of the same link must produce two clicks, and `link.clicks_count += 1`
      # would lose one of them.
      Link.update_counters(link_id, clicks_count: 1)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
