# frozen_string_literal: true

require "rails_helper"

# T057, D4, FR-020. The other end of the redirect path: what the middleware
# pushes in five seconds, this writes in two statements.
#
# The numbers a creator sees are produced here, so "expendable" applies to a
# batch lost in a crash and to nothing else — what is written must be exact.
RSpec.describe Clicks::FlushJob do
  let(:link) { create(:link) }
  let(:other_link) { create(:link) }

  def buffer(link_id, at: Time.current, times: 1)
    entries = Array.new(times) { "#{link_id}:#{(at.to_f * 1000).round}" }

    REDIS.with { |redis| redis.lpush(described_class::BUFFER_KEY, entries) }
  end

  def buffered = REDIS.with { |redis| redis.llen(described_class::BUFFER_KEY) }

  describe "draining the buffer" do
    it "writes one row per buffered click and empties the buffer" do
      buffer(link.id, times: 3)

      described_class.new.perform

      expect(Click.where(link_id: link.id).count).to eq(3)
      expect(buffered).to eq(0)
    end

    it "moves the counter by the number of clicks, not by one per batch" do
      buffer(link.id, times: 3)

      expect { described_class.new.perform }.to change { link.reload.clicks_count }.from(0).to(3)
    end

    it "keeps each link's clicks to itself when a batch spans several" do
      buffer(link.id, times: 2)
      buffer(other_link.id, times: 5)

      described_class.new.perform

      expect(link.reload.clicks_count).to eq(2)
      expect(other_link.reload.clicks_count).to eq(5)
    end

    # The counter is a summary of the rows. A run that moved one without the
    # other would put the dashboard permanently out of step with the data behind
    # it, and nothing would ever correct it.
    it "leaves the counter agreeing with the rows it wrote" do
      buffer(link.id, times: 7)

      described_class.new.perform

      expect(link.reload.clicks_count).to eq(Click.where(link_id: link.id).count)
    end

    it "records when the click happened, not when the flush ran" do
      clicked_at = 3.minutes.ago

      buffer(link.id, at: clicked_at)

      described_class.new.perform

      expect(Click.sole.occurred_at).to be_within(1.second).of(clicked_at)
    end

    it "does nothing at all when there is nothing buffered" do
      expect { described_class.new.perform }.not_to change(Click, :count)
    end
  end

  describe "batch atomicity" do
    # `LPOP key count` removes the entries as it reads them, which is what lets
    # this job run on a schedule without a lock: a second worker arriving mid-run
    # finds an empty list rather than the same clicks (D4).
    it "does not count a batch twice when it runs again" do
      buffer(link.id, times: 4)

      2.times { described_class.new.perform }

      expect(link.reload.clicks_count).to eq(4)
      expect(Click.count).to eq(4)
    end

    it "takes the entries out of the buffer as it reads them" do
      buffer(link.id, times: 2)

      allow(Click).to receive(:insert_all).and_wrap_original do |original, *args|
        expect(buffered).to eq(0)

        original.call(*args)
      end

      described_class.new.perform
    end

    # A single run keeps going until the buffer is empty. One batch per run at
    # this schedule would fall permanently behind the traffic the cache exists
    # to serve — the buffer would grow rather than drain.
    it "keeps draining past a single batch" do
      buffer(link.id, times: described_class::BATCH_SIZE + 5)

      described_class.new.perform

      expect(link.reload.clicks_count).to eq(described_class::BATCH_SIZE + 5)
      expect(buffered).to eq(0)
    end
  end

  describe "an entry it cannot read" do
    # Only a truncated write or a future change to the buffer's format can
    # produce one, and neither is worth discarding the thousand good clicks
    # around it.
    it "drops the entry and writes the rest of the batch" do
      REDIS.with { |redis| redis.lpush(described_class::BUFFER_KEY, "nonsense") }
      buffer(link.id, times: 2)

      described_class.new.perform

      expect(link.reload.clicks_count).to eq(2)
      expect(buffered).to eq(0)
    end
  end
end
