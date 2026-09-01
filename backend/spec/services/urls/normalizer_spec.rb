# frozen_string_literal: true

require "rails_helper"

RSpec.describe Urls::Normalizer do
  def normalize(url) = described_class.call(url)

  describe "the transformations that preserve meaning" do
    it "lowercases the scheme and the host but never the path" do
      expect(normalize("HTTPS://Example.COM/Campaign/Spring")).to eq("https://example.com/Campaign/Spring")
    end

    it "drops the port when it is the default for the scheme" do
      expect(normalize("https://example.com:443/x")).to eq("https://example.com/x")
      expect(normalize("http://example.com:80/x")).to eq("http://example.com/x")
    end

    it "keeps a port that is not the default" do
      expect(normalize("https://example.com:8443/x")).to eq("https://example.com:8443/x")
    end

    it "drops the trailing dot that names the same host" do
      expect(normalize("https://example.com./x")).to eq("https://example.com/x")
    end

    it "gives an empty path its slash" do
      expect(normalize("https://example.com")).to eq("https://example.com/")
    end

    it "drops an empty query and an empty fragment" do
      expect(normalize("https://example.com/x?")).to eq("https://example.com/x")
      expect(normalize("https://example.com/x#")).to eq("https://example.com/x")
    end

    it "trims surrounding whitespace, which is what pasting produces" do
      expect(normalize("  https://example.com/x\n")).to eq("https://example.com/x")
    end

    it "assumes https for a bare host, which is what a browser bar yields" do
      expect(normalize("example.com/x")).to eq("https://example.com/x")
    end
  end

  # The other half of FR-008, and the more important half: a shortener that
  # quietly sends a visitor somewhere other than where the creator pointed it
  # has failed at its only job.
  describe "the transformations it refuses to make" do
    it "leaves query parameters in their original order" do
      expect(normalize("https://example.com/x?b=2&a=1")).to eq("https://example.com/x?b=2&a=1")
    end

    it "keeps utm parameters, which are the whole point for the creator" do
      url = "https://example.com/x?utm_source=poster&utm_campaign=spring"

      expect(normalize(url)).to eq(url)
    end

    it "keeps a trailing slash on a non-empty path, which some servers treat as a different page" do
      expect(normalize("https://example.com/blog/")).to eq("https://example.com/blog/")
    end

    it "leaves percent-encoding alone" do
      expect(normalize("https://example.com/a%20b")).to eq("https://example.com/a%20b")
    end

    it "keeps the fragment when there is one" do
      expect(normalize("https://example.com/x#section-2")).to eq("https://example.com/x#section-2")
    end

    it "does not case-fold the query string" do
      expect(normalize("https://example.com/x?Token=AbC")).to eq("https://example.com/x?Token=AbC")
    end
  end

  describe "rejection" do
    it "refuses a blank destination as invalid_url" do
      expect { normalize("   ") }.to raise_error(Links::Rejection) { |error| expect(error.code).to eq("invalid_url") }
    end

    it "refuses a string with no host as invalid_url" do
      expect { normalize("https://") }.to raise_error(Links::Rejection) { |error| expect(error.code).to eq("invalid_url") }
    end

    it "refuses an unparseable address as invalid_url" do
      expect { normalize("http://exa mple.com") }.to raise_error(Links::Rejection) { |error| expect(error.code).to eq("invalid_url") }
    end

    # Scheme rejection is Urls::SafetyValidator's job, not this one's — the
    # normalizer's contract is "canonical form or invalid_url", and an ftp
    # address is perfectly well formed.
    it "case-folds a non-http scheme rather than judging it" do
      expect(normalize("FTP://Example.com/x")).to eq("ftp://Example.com/x")
    end

    # These two never survive Urls::SafetyValidator, but they have to reach it
    # to be refused for the right reason. A scheme with no authority after it
    # is the case the normalizer used to swallow: `data:` has no `//`, so it
    # was treated as a schemeless address, prefixed with `https://`, and then
    # rejected as `invalid_url` — a code that says the address is malformed
    # when the truth is that we refuse to shorten it.
    it "hands an opaque scheme onward rather than mistaking it for a hostname" do
      expect(normalize("DATA:text/html,<script>alert(1)</script>"))
        .to eq("data:text/html,<script>alert(1)</script>")
    end

    it "hands javascript: onward for the same reason" do
      expect(normalize("javascript:alert(1)")).to eq("javascript:alert(1)")
    end

    # The other side of that coin, and the reason the scheme test is not simply
    # "characters, then a colon": a host with an explicit port looks exactly
    # like an opaque scheme until you notice that what follows the colon is a
    # port number.
    it "still reads a host with an explicit port as a host" do
      expect(normalize("example.com:8080/x")).to eq("https://example.com:8080/x")
      expect(normalize("localhost:3000/x")).to eq("https://localhost:3000/x")
    end
  end
end
