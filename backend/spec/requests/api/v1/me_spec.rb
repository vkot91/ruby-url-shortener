# frozen_string_literal: true

require "rails_helper"

# `GET /api/v1/me`. It exists because the alternative was a readable cookie the
# BFF wrote at sign-in carrying the same two fields, and a cookie cannot answer
# the question this endpoint answers: it reports what was true when the session
# opened, not what is true now.
RSpec.describe "GET /api/v1/me", type: :request do
  let(:account) { create(:account, email: "creator@snip.test") }

  def get_me(headers = { "Authorization" => "Bearer #{Auth::AccessToken.encode(account)}" })
    get "/api/v1/me", headers: headers
  end

  it "answers with the caller's account" do
    get_me

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["account"]).to include(
      "id" => account.id,
      "email" => "creator@snip.test",
      "role" => "creator",
      "plan" => "free"
    )
  end

  it "reads the row rather than the token, so a role change shows up here first" do
    token = Auth::AccessToken.encode(account)

    account.update!(role: "admin")

    get_me("Authorization" => "Bearer #{token}")

    expect(response.parsed_body.dig("account", "role")).to eq("admin")
  end

  # The counterpart to the line above, and the reason the role is display only:
  # the *token* is still what decides what the caller may do, so a stale token
  # saying `creator` keeps them out of the admin surface until it is refreshed
  # (research.md D10). The two answers being allowed to disagree for fifteen
  # minutes is only safe while nothing authorises on this one.
  it "does not carry authority — the token still decides that" do
    expect(AccountSerializer.call(account).keys).to contain_exactly(
      :id, :email, :role, :plan, :created_at
    )
  end

  it "never reports whether the account is banned" do
    account.update!(banned_at: Time.current)

    expect(AccountSerializer.call(account.reload)).not_to have_key(:banned_at)
  end

  it "carries no password digest" do
    expect(AccountSerializer.call(account).values.map(&:to_s)).not_to include(account.password_digest)
  end

  describe "authentication" do
    it "refuses an anonymous caller" do
      get_me({})

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    # The distinction the whole client design rests on: this is the code that
    # means "refresh and retry", and the browser reaches this endpoint before
    # any other, so it is the one most likely to raise it.
    it "reports an aged-out token as token_expired" do
      token = Auth::AccessToken.encode(account)

      travel_to(Auth::AccessToken::LIFETIME.from_now + 1.second) do
        get_me("Authorization" => "Bearer #{token}")
      end

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("token_expired")
    end

    it "accepts the browser's cookie exactly as it accepts the header" do
      get_me("HTTP_COOKIE" => "#{Authentication::ACCESS_COOKIE}=#{Auth::AccessToken.encode(account)}")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("account", "email")).to eq("creator@snip.test")
    end

    it "sets no cookie of its own" do
      get_me

      expect(response.headers["set-cookie"]).to be_nil
    end
  end
end
