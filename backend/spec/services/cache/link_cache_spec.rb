# frozen_string_literal: true

require "rails_helper"

# T045. The cache's two jobs: hold everything a redirect decision needs in one
# value, and keep a link alive in Redis for as long as people are clicking it
# (D6).
RSpec.describe Cache::LinkCache do
  let(:entry) do
    described_class::Entry.new(
      link_id: SecureRandom.uuid,
      destination_url: "https://example.com/destination",
      banned: false,
      deleted: false,
      account_banned: false,
      account_id: SecureRandom.uuid
    )
  end

  def ttl_of(code) = REDIS.with { |redis| redis.ttl(described_class.key(code)) }

  describe "refreshing the TTL on read (D6)" do
    # The failure this prevents: a link that is popular for a day expires at the
    # moment it is hottest, because its 24 hours were counted from the write.
    # Every read pushes the expiry back out, so eviction tracks coldness.
    it "extends the expiry to a fresh 24 hours on every read" do
      described_class.write("abc1234", entry)

      REDIS.with { |redis| redis.expire(described_class.key("abc1234"), 60) }

      expect { described_class.read("abc1234") }
        .to change { ttl_of("abc1234") }
        .from(a_value_within(2).of(60))
        .to(a_value_within(2).of(described_class::TTL.to_i))
    end

    it "returns the stored value while it does so, in one round trip" do
      described_class.write("abc1234", entry)

      expect(described_class.read("abc1234")).to eq(described_class.pack(entry))
    end

    # A `GETEX` on a key that is not there must not create one — otherwise a
    # miss would leave an empty entry behind and the rebuild would never run.
    it "answers nil for an absent code without writing anything" do
      expect(described_class.read("absent1")).to be_nil
      expect(ttl_of("absent1")).to eq(-2)
    end
  end

  describe "the packed value" do
    it "carries the destination and the link id, so a hit needs no second lookup" do
      unpacked = described_class.unpack(described_class.pack(entry))

      expect(unpacked.destination_url).to eq("https://example.com/destination")
      expect(unpacked.link_id).to eq(entry.link_id)
    end

    it "carries the three flags a redirect decision branches on" do
      entry.banned = true
      entry.account_banned = true

      unpacked = described_class.unpack(described_class.pack(entry))

      expect(unpacked).to be_banned
      expect(unpacked).to be_account_banned
      expect(unpacked).not_to be_deleted
    end

    # The flags are independent, and a bitmask that runs them together would be
    # a redirect served to a banned link's visitor.
    it "keeps a deleted link distinguishable from a banned one" do
      entry.deleted = true

      unpacked = described_class.unpack(described_class.pack(entry))

      expect(unpacked).to be_deleted
      expect(unpacked).not_to be_banned
    end

    # Destination URLs are arbitrary strings and the separator is a legal
    # character in a query string. Splitting on every separator would truncate
    # exactly the destinations that carry parameters.
    it "survives a destination containing the separator character" do
      entry.destination_url = "https://example.com/search?a=1|2&b=3"

      unpacked = described_class.unpack(described_class.pack(entry))

      expect(unpacked.destination_url).to eq("https://example.com/search?a=1|2&b=3")
    end
  end

  describe "writing" do
    it "expires the entry after 24 hours" do
      described_class.write("abc1234", entry)

      expect(ttl_of("abc1234")).to be_within(2).of(described_class::TTL.to_i)
    end

    # D14. Banning an account has to reach every cached link it owns, and
    # `link:<code>` is keyed by code alone. The set is built on the miss path so
    # the ban does not have to SCAN the keyspace for them.
    it "records the code against its account, so an account ban can find it" do
      described_class.write("abc1234", entry)

      members = REDIS.with { |redis| redis.smembers(described_class.account_codes_key(entry.account_id)) }

      expect(members).to eq([ "abc1234" ])
    end

    it "bounds the account's set with an expiry rather than letting it grow forever" do
      described_class.write("abc1234", entry)

      ttl = REDIS.with { |redis| redis.ttl(described_class.account_codes_key(entry.account_id)) }

      expect(ttl).to be_within(2).of(described_class::ACCOUNT_CODES_TTL.to_i)
    end
  end

  describe "deleting" do
    it "removes the entry so the next read rebuilds it" do
      described_class.write("abc1234", entry)

      described_class.delete("abc1234")

      expect(described_class.read("abc1234")).to be_nil
    end

    # Invalidation is fired from a model callback that cannot know whether the
    # link was ever cached, so deleting nothing has to be an ordinary outcome.
    it "is a no-op on a code that was never cached" do
      expect { described_class.delete("nevercached") }.not_to raise_error
    end
  end
end
