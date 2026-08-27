# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::AccessToken do
  let(:account) { create(:account) }

  describe ".decode" do
    it "round-trips the claims an authenticated request needs" do
      claims = described_class.decode(described_class.encode(account))

      expect(claims.account_id).to eq(account.id)
      expect(claims.role).to eq(account.role)
      expect(claims.jti).to be_present
    end

    # The whole point of the access token. If verifying one ever needs a row,
    # the stateless goal in research.md D10 has quietly been abandoned.
    it "verifies without issuing a database query" do
      token = described_class.encode(account)

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] unless payload[:name] == "SCHEMA"
      end

      begin
        described_class.decode(token)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(queries).to be_empty
    end

    it "rejects a token whose payload was edited" do
      token = described_class.encode(account)
      header, _payload, signature = token.split(".")
      forged = Base64.urlsafe_encode64({ sub: "999", role: "admin", jti: "x", exp: 1.hour.from_now.to_i }.to_json, padding: false)

      expect { described_class.decode([ header, forged, signature ].join(".")) }
        .to raise_error(described_class::Invalid)
    end

    # The classic JWT attack: strip the signature and tell the verifier the
    # token is unsigned. Pinning `algorithm:` on decode is what refuses it.
    it "rejects an unsigned token claiming alg: none" do
      unsigned = JWT.encode({ sub: account.id.to_s, role: "admin", jti: "x", exp: 1.hour.from_now.to_i }, nil, "none")

      expect { described_class.decode(unsigned) }.to raise_error(described_class::Invalid)
    end

    it "rejects a token signed with the wrong secret" do
      foreign = JWT.encode({ sub: account.id.to_s, role: "creator", jti: "x", exp: 1.hour.from_now.to_i }, "not-our-secret", "HS256")

      expect { described_class.decode(foreign) }.to raise_error(described_class::Invalid)
    end

    it "distinguishes an expired token from an invalid one" do
      token = travel_to(2.hours.ago) { described_class.encode(account) }

      expect { described_class.decode(token) }.to raise_error(described_class::Expired)
    end

    it "rejects a token missing the claims authorization depends on" do
      incomplete = JWT.encode({ sub: account.id.to_s, exp: 1.hour.from_now.to_i }, described_class.send(:secret), "HS256")

      expect { described_class.decode(incomplete) }.to raise_error(described_class::Invalid)
    end

    it "rejects garbage" do
      expect { described_class.decode("not-a-token") }.to raise_error(described_class::Invalid)
    end
  end
end
