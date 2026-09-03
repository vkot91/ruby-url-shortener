# frozen_string_literal: true

require "rails_helper"

# T046, D7, SC-007. Enumeration is ordinary traffic for a shortener: someone
# walking the code space produces a stream of requests for codes that do not
# exist, and without a record of the absence every one of them is a Postgres
# query.
RSpec.describe Cache::NegativeCache do
  def value_of(code) = REDIS.with { |redis| redis.get(Cache::LinkCache.key(code)) }

  def ttl_of(code) = REDIS.with { |redis| redis.ttl(Cache::LinkCache.key(code)) }

  it "records an absent code under the same key a real link would use" do
    described_class.write("absent1")

    expect(value_of("absent1")).to eq(described_class::SENTINEL)
  end

  # One key space, not two. It is what keeps the hot path at a single round
  # trip, and it is why invalidating a code clears its absence for free.
  it "is recognisable to the reader without a second lookup" do
    described_class.write("absent1")

    expect(described_class).to be_absent(Cache::LinkCache.read("absent1"))
  end

  it "does not mistake a cached link for an absence" do
    entry = Cache::LinkCache::Entry.new(
      link_id: SecureRandom.uuid,
      destination_url: "https://example.com",
      banned: false, deleted: false, account_banned: false,
      account_id: SecureRandom.uuid
    )

    expect(described_class).not_to be_absent(Cache::LinkCache.pack(entry))
  end

  it "treats a cache miss as a miss rather than as an absence" do
    expect(described_class).not_to be_absent(nil)
  end

  describe "the 60-second expiry" do
    # An absence is the one cached fact that a *different* row's creation makes
    # wrong. `after_commit` invalidation covers the ordinary case (T058); the
    # short TTL is what bounds the damage when it does not run — a minute of a
    # working link answering 404, rather than a day of it.
    it "expires after a minute, not after the 24 hours a link gets" do
      described_class.write("absent1")

      expect(ttl_of("absent1")).to be_within(2).of(described_class::TTL.to_i)
      expect(described_class::TTL).to be < Cache::LinkCache::TTL
    end

    it "is gone once the minute has passed" do
      described_class.write("absent1")

      # Redis expiry is server-side, so the clock that matters is not Ruby's:
      # the key is aged by hand rather than by travelling in time.
      REDIS.with { |redis| redis.expire(Cache::LinkCache.key("absent1"), 0) }

      expect(Cache::LinkCache.read("absent1")).to be_nil
    end
  end
end
