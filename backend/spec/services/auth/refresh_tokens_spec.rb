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
  #
  # Every example here replays the token *after* the grace window, because that
  # is where theft actually happens: a copy taken from a log, a backup, or a
  # proxy is not spent in the same ten seconds as the original. The window
  # itself is the next describe block.
  def after_grace = travel(described_class::GRACE + 1.second)

  describe "reuse detection" do
    it "revokes the whole family when an already-exchanged token comes back" do
      original = described_class.issue(account: account)
      successor = described_class.rotate(original.token)

      after_grace

      expect { described_class.rotate(original.token) }.to raise_error(described_class::Reused)

      expect(successor.reload).to be_revoked
    end

    # Revoking only the replayed token would leave the thief holding a live
    # successor, which is the situation reuse detection exists to end.
    it "kills the successor the thief is holding, not just the replayed token" do
      original = described_class.issue(account: account)
      successor = described_class.rotate(original.token)

      after_grace

      suppress(described_class::Reused) { described_class.rotate(original.token) }

      expect { described_class.rotate(successor.token) }.to raise_error(described_class::Invalid)
    end

    it "leaves other families of the same account alone" do
      other_device = described_class.issue(account: account)
      compromised = described_class.issue(account: account)
      described_class.rotate(compromised.token)

      after_grace

      expect { described_class.rotate(compromised.token) }.to raise_error(described_class::Reused)

      expect(other_device.reload).not_to be_revoked
    end
  end

  # The other cause of "presented twice", and the reason the window exists.
  #
  # Two browser tabs whose access tokens expire in the same second send the same
  # refresh token milliseconds apart. Before this window, the second one revoked
  # the family and signed the person out of both — a bug that fired on ordinary
  # use and was indistinguishable, from the server's side, from the attack it
  # was meant to catch.
  describe "the rotation grace window" do
    it "treats a replay within the window as the same client retrying" do
      original = described_class.issue(account: account)
      described_class.rotate(original.token)

      expect { described_class.rotate(original.token) }.not_to raise_error
    end

    it "keeps the session alive rather than revoking the family" do
      original = described_class.issue(account: account)
      first = described_class.rotate(original.token)

      second = described_class.rotate(original.token)

      expect(first.reload).not_to be_revoked
      expect(second.reload).not_to be_revoked
      expect(second.family_id).to eq(first.family_id)
    end

    # The cost, stated rather than discovered: only the digest is stored, so the
    # first successor's raw string cannot be handed back and a second one is
    # issued instead. For up to ten seconds a family carries two live tokens.
    it "issues a second successor, since the first one's raw token is unrecoverable" do
      original = described_class.issue(account: account)
      first = described_class.rotate(original.token)
      second = described_class.rotate(original.token)

      expect(second.token).not_to eq(first.token)
      expect(RefreshToken.where(family_id: first.family_id, revoked_at: nil, used_at: nil).count).to eq(2)
    end

    it "closes exactly at the boundary, so the window cannot be widened by waiting" do
      original = described_class.issue(account: account)
      described_class.rotate(original.token)

      after_grace

      expect { described_class.rotate(original.token) }.to raise_error(described_class::Reused)
    end

    # The window forgives a replay of a *used* token. It must not forgive one of
    # a token the family already revoked, or a theft detected a minute ago would
    # be re-admitted by a retry ten seconds later.
    it "never forgives a token whose family has already been revoked" do
      original = described_class.issue(account: account)
      described_class.rotate(original.token)
      described_class.revoke_family(original.family_id)

      expect { described_class.rotate(original.token) }.to raise_error(described_class::Invalid)
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
