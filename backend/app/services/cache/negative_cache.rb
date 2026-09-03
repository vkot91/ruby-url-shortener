# frozen_string_literal: true

module Cache
  # Codes confirmed absent from Postgres (T048, D7, FR-017, SC-007).
  #
  # Enumeration of random codes is ordinary traffic for any shortener, and
  # without this every attempt is a Postgres query on a path that must not touch
  # Postgres. The absent code is recorded under the *same* `link:<code>` key as
  # a real entry, as a sentinel string: one key space rather than two means the
  # hot path still makes exactly one round trip, and an invalidation that
  # deletes `link:<code>` clears a stale absence for free — which is what makes
  # a code created seconds after somebody probed it resolve immediately (T058).
  module NegativeCache
    # Deliberately not a value `LinkCache.unpack` could produce: it has no
    # separator in it, so a packed entry can never be mistaken for an absence
    # and an absence can never be parsed as a destination.
    SENTINEL = "__404__"

    # 60 seconds, not 24 hours. An absence is the one cached fact that becomes
    # wrong through no write of its own — a code goes from absent to present
    # when somebody creates it — and while `after_commit` invalidation covers
    # that (D2), the short TTL means a missed invalidation costs a minute rather
    # than a day.
    TTL = 60.seconds

    def self.absent?(raw) = raw == SENTINEL

    def self.write(code)
      REDIS.with { |redis| redis.set(LinkCache.key(code), SENTINEL, ex: TTL.to_i) }
    end
  end
end
