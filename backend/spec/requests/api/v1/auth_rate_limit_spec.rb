# frozen_string_literal: true

require "rails_helper"

# FR-036. Registration, sign-in, and refresh are the three doors an attacker can
# knock on without an account, so all three count.
RSpec.describe "Authentication rate limits", type: :request do
  let(:password) { "a-sufficiently-long-passphrase" }

  def register(email:, from: "203.0.113.10")
    post "/api/v1/registrations",
         params: { email: email, password: password },
         headers: { "REMOTE_ADDR" => from },
         as: :json
  end

  def sign_in(email:, password: "wrong-but-long-enough", from: "203.0.113.10")
    post "/api/v1/sessions",
         params: { email: email, password: password },
         headers: { "REMOTE_ADDR" => from },
         as: :json
  end

  describe "registration, per origin" do
    it "refuses the eleventh attempt from one address within the hour" do
      10.times { |n| register(email: "creator#{n}@example.com") }

      expect(response).to have_http_status(:created)

      register(email: "creator-eleven@example.com")

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body.dig("error", "code")).to eq("rate_limited")
    end

    it "leaves a different origin unaffected, since the limit is per origin" do
      11.times { |n| register(email: "creator#{n}@example.com") }

      register(email: "elsewhere@example.com", from: "203.0.113.99")

      expect(response).to have_http_status(:created)
    end

    it "lets the same origin back in once the window has passed" do
      11.times { |n| register(email: "creator#{n}@example.com") }

      travel(RateLimiting::WINDOW + 1.minute) do
        register(email: "later@example.com")
      end

      expect(response).to have_http_status(:created)
    end
  end

  describe "sign-in, per origin" do
    let!(:account) { create(:account, email: "creator@example.com", password: password) }

    it "refuses the eleventh attempt from one address, even with the right password" do
      10.times { sign_in(email: account.email) }

      sign_in(email: account.email, password: password)

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "sign-in, per email address" do
    let!(:account) { create(:account, email: "creator@example.com", password: password) }

    # The point of the second limiter: without it, the per-origin limit is
    # bypassed by spreading one password list across a botnet, which is what
    # credential stuffing actually looks like.
    it "refuses the sixth attempt against one address however many origins it comes from" do
      5.times { |n| sign_in(email: account.email, from: "203.0.113.#{n}") }

      sign_in(email: account.email, from: "203.0.113.200")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts the address case-insensitively, since the column is citext" do
      5.times { sign_in(email: "CREATOR@example.com") }

      sign_in(email: "creator@example.com")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "leaves a different address unaffected" do
      6.times { sign_in(email: account.email) }

      sign_in(email: "someone-else@example.com", from: "203.0.113.201")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # FR-036's second sentence, and the reason the sign-in limiter does not use
  # the generic `rate_limited` body the other two do.
  #
  # A limiter keyed on the email address is itself an oracle if its refusal
  # looks different from an ordinary failure: knock six times, and a different
  # response for a registered address than for an unregistered one hands over
  # exactly the fact the requirement forbids disclosing.
  describe "the refusal body" do
    let!(:registered) { create(:account, email: "registered@example.com", password: password) }

    def exhaust_and_capture(email)
      6.times { sign_in(email: email, from: "203.0.113.77") }

      [ response.status, response.body ]
    end

    it "is identical for a registered and an unregistered address" do
      registered_refusal = exhaust_and_capture(registered.email)

      RATE_LIMIT_STORE.clear

      unregistered_refusal = exhaust_and_capture("nobody@example.com")

      expect(registered_refusal).to eq(unregistered_refusal)
      expect(registered_refusal.first).to eq(429)
    end

    # And identical to the 401 body as well, so an attacker cannot even learn
    # that the limiter counting this address has been touched
    # (contracts/openapi.yaml `/sessions` 429).
    it "is identical to the body of an ordinary failed sign-in" do
      sign_in(email: registered.email)
      unthrottled = response.body

      expect(response).to have_http_status(:unauthorized)

      5.times { sign_in(email: registered.email) }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to eq(unthrottled)
    end
  end

  describe "refresh, per origin" do
    it "refuses past its hourly allowance" do
      60.times { post "/api/v1/auth/refresh", params: { refresh_token: "nope" }, as: :json }

      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/auth/refresh", params: { refresh_token: "nope" }, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
