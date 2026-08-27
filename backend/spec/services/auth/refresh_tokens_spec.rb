# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::RefreshTokens do
  let(:account) { create(:account) }

  describe ".issue" do
    it "returns the raw token once and stores only its digest" do
      token = described_class.issue(account: account)

      expect(token.token).to be_present
      expect(token.token_digest).not_to eq(token.token)
      expect(RefreshToken.find(token.id).token).to be_nil
    end

    it "opens a new family per sign-in" do
      first = described_class.issue(account: account)
      second = described_class.issue(account: account)

      expect(second.family_id).not_to eq(first.family_id)
    end
  end

  describe ".rotate" do
    it "issues a successor inside the same family" do
      original = described_class.issue(account: account)

      successor = described_class.rotate(original.token)

      expect(successor.family_id).to eq(original.family_id)
      expect(successor.token).not_to eq(original.token)
      expect(successor.account).to eq(account)
    end

    it "marks the exchanged token used" do
      original = described_class.issue(account: account)

      described_class.rotate(original.token)

      expect(original.reload).to be_used
    end

    it "refuses a token that was never issued" do
      expect { described_class.rotate("never-issued") }.to raise_error(described_class::Invalid)
    end

    it "refuses a blank token without querying" do
      expect { described_class.rotate(nil) }.to raise_error(described_class::Invalid)
      expect { described_class.rotate("") }.to raise_error(described_class::Invalid)
    end

    it "refuses an expired token" do
      original = described_class.issue(account: account)
      original.update!(expires_at: 1.second.ago)

      expect { described_class.rotate(original.token) }.to raise_error(described_class::Invalid)
    end

    it "refuses a revoked token without treating it as a breach" do
      original = described_class.issue(account: account)
      successor = described_class.rotate(original.token)
      described_class.revoke_family(original.family_id)

      expect { described_class.rotate(successor.token) }.to raise_error(described_class::Invalid)
    end
  end

  # This is the part that makes rotation worth doing. Without it, a stolen token
  # is used once and nobody ever finds out.
  describe "reuse detection" do
    it "revokes the whole family when an already-exchanged token comes back" do
      original = described_class.issue(account: account)
      successor = described_class.rotate(original.token)

      expect { described_class.rotate(original.token) }.to raise_error(described_class::Reused)

      expect(successor.reload).to be_revoked
    end

    # Revoking only the replayed token would leave the thief holding a live
    # successor, which is the situation reuse detection exists to end.
    it "kills the successor the thief is holding, not just the replayed token" do
      original = described_class.issue(account: account)
      successor = described_class.rotate(original.token)

      suppress(described_class::Reused) { described_class.rotate(original.token) }

      expect { described_class.rotate(successor.token) }.to raise_error(described_class::Invalid)
    end

    it "leaves other families of the same account alone" do
      other_device = described_class.issue(account: account)
      compromised = described_class.issue(account: account)
      described_class.rotate(compromised.token)

      expect { described_class.rotate(compromised.token) }.to raise_error(described_class::Reused)

      expect(other_device.reload).not_to be_revoked
    end
  end

  describe ".revoke_all_for" do
    it "is triggered by banning the account, not by the controller that bans it" do
      first = described_class.issue(account: account)
      second = described_class.issue(account: account)

      account.update!(banned_at: Time.current)

      expect(first.reload).to be_revoked
      expect(second.reload).to be_revoked
    end
  end
end
