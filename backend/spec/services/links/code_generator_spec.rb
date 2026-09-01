# frozen_string_literal: true

require "rails_helper"

RSpec.describe Links::CodeGenerator do
  describe ".generate" do
    it "draws 7 characters from letters and digits (FR-009)" do
      codes = Array.new(200) { described_class.generate }

      expect(codes).to all(match(/\A[A-Za-z0-9]{7}\z/))
    end

    it "does not produce the same code twice in a run, which a sequence would make trivial" do
      codes = Array.new(500) { described_class.generate }

      expect(codes.uniq.size).to eq(500)
    end

    it "uses the whole alphabet rather than a corner of it" do
      characters = Array.new(500) { described_class.generate }.join.chars.uniq

      expect(characters.size).to eq(Links::CodeGenerator::ALPHABET.size)
    end

    # FR-012. `favicon`, `sitemap`, and `signup` are all reachable by a
    # seven-character draw, and a code the router swallows is a code that never
    # redirects.
    it "redraws when the draw lands on a reserved word" do
      reserved = "favicon".chars.map { |character| Links::CodeGenerator::ALPHABET.index(character) }
      replacement = Array.new(7, 0)

      allow(SecureRandom).to receive(:random_number).and_return(*(reserved + replacement))

      expect(described_class.generate).to eq("0000000")
    end
  end

  describe ".allocate" do
    let(:account) { create(:account) }

    def create_link(code) = Link.create!(account: account, code: code, destination_url: "https://example.com/x")

    it "hands the block a code and returns what the block returns" do
      link = described_class.allocate { |code| create_link(code) }

      expect(link).to be_persisted
      expect(link.code).to match(/\A[A-Za-z0-9]{7}\z/)
    end

    # Principle III, D3. The unique index *is* the allocation algorithm.
    it "retries with a fresh code when the store rejects the first one as taken" do
      taken = described_class.generate
      create_link(taken)

      attempted = []

      link = described_class.allocate do |code|
        attempted << code

        create_link(attempted.size == 1 ? taken : code)
      end

      expect(attempted.size).to eq(2)
      expect(link.code).not_to eq(taken)
    end

    # The bound exists so that a unique violation from some *other* column
    # cannot spin forever disguised as a code collision.
    it "gives up after MAX_ATTEMPTS rather than retrying forever" do
      attempts = 0

      expect do
        described_class.allocate do
          attempts += 1

          raise ActiveRecord::RecordNotUnique, "links_code_key"
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect(attempts).to eq(Links::CodeGenerator::MAX_ATTEMPTS)
    end

    # The point of the whole design, asserted directly: a SELECT followed by an
    # INSERT has a window between them that concurrency will find, so there is
    # no SELECT. If someone adds an `exists?` guard "to be safe", this fails.
    it "never asks the store whether a code is taken" do
      statements = []

      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statements << payload[:sql] unless payload[:name] == "SCHEMA"
      end

      begin
        described_class.allocate { |code| create_link(code) }
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(statements.grep(/SELECT.+FROM "links"/i)).to be_empty
      expect(statements.grep(/INSERT INTO "links"/i).size).to eq(1)
    end
  end
end
