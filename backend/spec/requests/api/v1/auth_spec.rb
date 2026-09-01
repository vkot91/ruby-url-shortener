# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Registration and sign-in", type: :request do
  let(:password) { "a-sufficiently-long-passphrase" }

  def token_pair = response.parsed_body

  # contracts/openapi.yaml `TokenPair`, asserted as a shape rather than by
  # eyeballing one response: the Next.js BFF and any future non-browser client
  # both read exactly these three keys.
  shared_examples "a token pair" do
    it "returns the three fields the contract names, and no others" do
      expect(response).to have_http_status(:created)
      expect(token_pair.keys).to match_array(%w[access_token refresh_token expires_in])
    end

    it "returns an access token this application will accept" do
      claims = Auth::AccessToken.decode(token_pair["access_token"])

      expect(claims.account_id).to eq(Account.find_by(email: email).id)
      expect(claims.role).to eq("creator")
    end

    it "returns a refresh token that is opaque rather than a second JWT (D10)" do
      expect(token_pair["refresh_token"]).not_to include(".")
      expect(token_pair["refresh_token"]).to be_present
    end

    it "reports the access token's real lifetime rather than a hard-coded 900" do
      expect(token_pair["expires_in"]).to eq(Auth::AccessToken::LIFETIME.to_i)
    end

    # FR-015 and Principle V. ActionDispatch::Cookies is not in the middleware
    # stack at all, so this is structural — but it is asserted on the paths a
    # framework upgrade would most plausibly re-introduce it on.
    it "sets no cookie" do
      expect(response.headers["set-cookie"]).to be_nil
    end
  end

  describe "POST /api/v1/registrations" do
    let(:email) { "new-creator@example.com" }

    context "with a valid email and password" do
      before { post "/api/v1/registrations", params: { email: email, password: password }, as: :json }

      it_behaves_like "a token pair"

      it "creates the account as a creator, never as an administrator (FR-003)" do
        expect(Account.find_by(email: email)).to be_creator
      end

      it "opens a refresh-token family, so the new account is already signed in" do
        expect(Account.find_by(email: email).refresh_tokens.count).to eq(1)
      end
    end

    it "treats the email as case-insensitive, because the column is citext" do
      create(:account, email: "taken@example.com")

      post "/api/v1/registrations", params: { email: "TAKEN@example.com", password: password }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details")).to include("email")
    end

    it "refuses a password shorter than the contract's minimum" do
      post "/api/v1/registrations", params: { email: email, password: "short" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details")).to include("password")
    end

    it "refuses a malformed email" do
      post "/api/v1/registrations", params: { email: "not-an-address", password: password }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "reports a missing parameter rather than raising" do
      post "/api/v1/registrations", params: { email: email }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("parameter_missing")
    end
  end

  describe "POST /api/v1/sessions" do
    let(:email) { "creator@example.com" }
    let!(:account) { create(:account, email: email, password: password) }

    context "with the right password" do
      before { post "/api/v1/sessions", params: { email: email, password: password }, as: :json }

      it_behaves_like "a token pair"

      it "opens a new family rather than extending the last one" do
        first_family = account.refresh_tokens.sole.family_id

        post "/api/v1/sessions", params: { email: email, password: password }, as: :json

        # Asserted as a set, not as "the last row". Primary keys are UUIDs, so
        # an unordered relation has no newest element — `.last` would return
        # whichever row sorts highest, which is unrelated to insertion order.
        families = account.refresh_tokens.pluck(:family_id).uniq

        expect(families.size).to eq(2)
        expect(families).to include(first_family)
      end
    end

    it "signs in whatever the case of the address" do
      post "/api/v1/sessions", params: { email: "CREATOR@example.com", password: password }, as: :json

      expect(response).to have_http_status(:created)
    end

    # FR-036's second sentence. An attacker who can tell "no such account" from
    # "wrong password" has an account enumerator.
    it "answers a wrong password and an unknown address identically" do
      post "/api/v1/sessions", params: { email: email, password: "wrong-but-long-enough" }, as: :json
      wrong_password = [ response.status, response.body ]

      post "/api/v1/sessions", params: { email: "nobody@example.com", password: password }, as: :json
      unknown_address = [ response.status, response.body ]

      expect(wrong_password).to eq(unknown_address)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_credentials")
    end

    it "refuses a banned account, in the same words" do
      account.update!(banned_at: Time.current)

      post "/api/v1/sessions", params: { email: email, password: password }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_credentials")
    end

    it "sets no cookie when it refuses either" do
      post "/api/v1/sessions", params: { email: email, password: "wrong-but-long-enough" }, as: :json

      expect(response.headers["set-cookie"]).to be_nil
    end
  end

  describe "DELETE /api/v1/sessions" do
    let(:account) { create(:account, password: password) }
    let(:refresh_token) { Auth::RefreshTokens.issue(account: account) }

    def sign_out(token)
      delete "/api/v1/sessions",
             params: { refresh_token: token },
             headers: { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" },
             as: :json
    end

    it "revokes the family, so the token cannot be exchanged afterwards" do
      sign_out(refresh_token.token)

      expect(response).to have_http_status(:no_content)
      expect { Auth::RefreshTokens.rotate(refresh_token.token) }.to raise_error(Auth::RefreshTokens::Invalid)
    end

    # Reporting "no such token" would let anyone holding a candidate string ask
    # us to confirm it.
    it "answers the same way for a token that never existed" do
      sign_out("not-a-real-token")

      expect(response).to have_http_status(:no_content)
    end

    it "requires a live access token, since sign-out is an account action" do
      delete "/api/v1/sessions", params: { refresh_token: refresh_token.token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
