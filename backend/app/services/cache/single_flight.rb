# frozen_string_literal: true

module Cache
  # One rebuild per expired key, not one per request that noticed (T049, D5,
  # SC-007).
  #
  # The failure this prevents is the spec's viral-link-at-expiry case: a key
  # holding a link everybody is clicking expires, and every request in flight
  # goes to Postgres at once. At 5 000 rps that is 5 000 identical queries in
  # the time it takes to answer one of them, which is how a read cache takes the
  # database down rather than protecting it.
  module SingleFlight
    def self.lock_key(code) = "lock:#{code}"

    # Long enough to cover a Postgres round trip and its retries, short enough
    # that a process dying mid-rebuild cannot wedge a code for longer than a
    # visitor would wait. Never released explicitly: releasing means deleting a
    # key that may by then belong to the *next* holder, and the expiry costs
    # nothing — by the time it fires the winner has long since published.
    LOCK_TTL = 5.seconds

    # A loser waits about this long in total before deciding the winner is not
    # coming and doing the work itself. Bounded on purpose: the alternative to
    # waiting is a Postgres query, and Principle I's ordering says a visitor
    # waiting on a lock held by a crashed process is worse than one extra query.
    WAIT_ATTEMPTS = 5
    WAIT_INTERVAL = 0.01

    # Yields to the winner. Losers re-read the cache a few times and take the
    # winner's value if it arrives, then fall back to rebuilding themselves.
    #
    # `read` is passed rather than assumed so this stays about coordination and
    # nothing else: it knows how to pick one caller, not what a link is.
    def self.resolve(code, read:)
      return yield if acquire(code)

      WAIT_ATTEMPTS.times do
        sleep WAIT_INTERVAL

        published = read.call

        return published if published
      end

      yield
    end

    # `SET NX EX` in one round trip. Two calls — an existence check and a set —
    # would have the same race between them that the lock exists to close
    # (Principle III).
    def self.acquire(code)
      REDIS.with { |redis| redis.set(lock_key(code), 1, nx: true, ex: LOCK_TTL.to_i) }
    end
  end
end
