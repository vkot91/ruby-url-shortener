# frozen_string_literal: true

require "rails_helper"

# The whole of research.md D10, walked end to end in one example: sign in,
# refresh, confirm the old token is dead, replay it anyway, and confirm the
# family is gone and the human has to sign in again.
#
# It is one example rather than five deliberately. Rotation with reuse detection
# is a sequence, and the property under test — that replaying a spent token
# costs you the session — only exists across the whole sequence. Split into
# steps, each piece passes while the guarantee is broken.
RSpec.describe "Access and refresh token lifecycle", type: :request do
  let(:password) { "a-sufficiently-long-passphrase" }
  let!(:account) { create(:account, email: "creator@example.com", password: password) }

  def sign_in
    post "/api/v1/sessions", params: { email: account.email, password: password }, as: :json

    response.parsed_body
  end

  def refresh(token)
    post "/api/v1/auth/refresh", params: { refresh_token: token }, as: :json

    response.parsed_body
  end

  def probe(access_token)
    post "/api/v1/links",
         params: { destination_url: "https://example.com/x" },
         headers: { "Authorization" => "Bearer #{access_token}" },
         as: :json
  end

  it "rotates on refresh, kills the spent token, and revokes the family on replay" do
    original = sign_in

    probe(original["access_token"])
    expect(response).to have_http_status(:created)

    rotated = refresh(original["refresh_token"])

    expect(response).to have_http_status(:created)
    expect(rotated["refresh_token"]).not_to eq(original["refresh_token"])
    expect(rotated["access_token"]).not_to eq(original["access_token"])

    # The successor works.
    probe(rotated["access_token"])
    expect(response).to have_http_status(:created)

    # The spent token does not. This is the "rotation" half.
    refresh(original["refresh_token"])

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("token_reuse_detected")

    # And this is the "detection" half — the half that makes the rotation worth
    # doing. The successor the legitimate client is holding is now dead too,
    # because from here there is no way to tell which of the two holders was
    # the thief.
    refresh(rotated["refresh_token"])

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_refresh_token")

    expect(account.refresh_tokens.where(revoked_at: nil)).to be_empty

    # Signing in again opens a fresh family and works.
    expect(sign_in["refresh_token"]).to be_present
    expect(response).to have_http_status(:created)
  end

  describe "the two 401s a client must tell apart (contracts/openapi.yaml)" do
    it "reports an expired access token as token_expired, meaning refresh and retry" do
      expired = travel_to(2.hours.ago) { Auth::AccessToken.encode(account) }

      probe(expired)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("token_expired")
    end

    it "reports an unknown refresh token as invalid_refresh_token, meaning sign in again" do
      refresh("not-a-real-token")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_refresh_token")
    end

    it "reports an expired refresh token as invalid_refresh_token rather than as reuse" do
      token = Auth::RefreshTokens.issue(account: account)
      token.update!(expires_at: 1.minute.ago)

      refresh(token.token)

      expect(response.parsed_body.dig("error", "code")).to eq("invalid_refresh_token")
    end
  end

  it "requires no live access token to refresh, since an expired one is why you are here" do
    original = sign_in

    refresh(original["refresh_token"])

    expect(response).to have_http_status(:created)
  end

  it "sets no cookie anywhere in the sequence (FR-015)" do
    original = sign_in
    expect(response.headers["set-cookie"]).to be_nil

    refresh(original["refresh_token"])
    expect(response.headers["set-cookie"]).to be_nil
  end
end
