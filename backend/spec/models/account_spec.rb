# frozen_string_literal: true

require "rails_helper"

# FR-018, D14. A ban must reach redirects already in the cache, including the
# hot ones the `account:<id>:codes` set would have missed.
RSpec.describe Account do
  describe "link cache on ban" do
    def cached?(code) = REDIS.with { |redis| redis.exists?(Cache::LinkCache.key(code)) }

    def seed_cache(*codes)
      REDIS.with { |redis| codes.each { |code| redis.set(Cache::LinkCache.key(code), "0|id|https://example.com") } }
    end

    let(:account) { create(:account) }
    let!(:live) { create(:link, account: account) }
    let!(:deleted) { create(:link, :deleted, account: account) }
    let!(:other) { create(:link) }

    before { seed_cache(live.code, deleted.code, other.code) }

    it "drops every cached link of the account when it is banned" do
      account.update!(banned_at: Time.current)

      expect([ cached?(live.code), cached?(deleted.code) ]).to eq([ false, false ])
    end

    it "leaves other accounts' cached links alone" do
      account.update!(banned_at: Time.current)

      expect(cached?(other.code)).to be(true)
    end

    it "drops them again on unban, since the cached flag is stale either way" do
      account.update!(banned_at: Time.current)
      seed_cache(live.code)

      account.update!(banned_at: nil)

      expect(cached?(live.code)).to be(false)
    end

    it "does nothing to the cache on an unrelated update" do
      account.update!(email: "renamed@example.com")

      expect(cached?(live.code)).to be(true)
    end
  end
end
