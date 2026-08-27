# frozen_string_literal: true

require "rails_helper"

# Phase 2 ships no endpoints, but it does ship the concern every later endpoint
# is built on and the logging cap Principle I depends on. This probe controller
# exists only here: it exercises them against a real request cycle rather than
# waiting for Phase 3 to discover they never worked.
class ProbesController < ApplicationController
  include Authentication

  allow_unauthenticated_access only: %i[open missing invalid]

  def open
    render json: { ok: true }
  end

  def guarded
    render json: { account_id: current_account_id, role: current_account_role }
  end

  # Reads the row rather than the claims, so the spec can tell the two apart.
  def guarded_with_record
    render json: { email: current_account.email }
  end

  def missing
    raise ActiveRecord::RecordNotFound
  end

  def invalid
    Account.create!(email: "", password: "")
  end
end

RSpec.describe "Foundational controller concerns", type: :request do
  # Routes, not records: the temporary probe routes must be drawn once for the
  # group and torn down after it, and nothing here touches the database, so the
  # usual state-leak objection to before(:all) does not apply.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      get "probes/open" => "probes#open"
      get "probes/guarded" => "probes#guarded"
      get "probes/guarded_with_record" => "probes#guarded_with_record"
      get "probes/missing" => "probes#missing"
      get "probes/invalid" => "probes#invalid"
    end
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.reload_routes!
  end

  let(:account) { create(:account) }

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  describe "authentication" do
    it "admits a request carrying a valid access token" do
      get "/probes/guarded", headers: bearer(Auth::AccessToken.encode(account))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["account_id"]).to eq(account.id)
      expect(response.parsed_body["role"]).to eq("creator")
    end

    it "refuses a request with no credential" do
      get "/probes/guarded"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    it "refuses a malformed Authorization header" do
      get "/probes/guarded", headers: { "Authorization" => "Basic abc123" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    it "refuses a forged token" do
      forged = JWT.encode({ sub: account.id.to_s, role: "admin", jti: "x", exp: 1.hour.from_now.to_i }, "wrong", "HS256")

      get "/probes/guarded", headers: bearer(forged)

      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    # The client has to be able to tell "refresh and retry" from "sign in
    # again", or it will do the wrong one.
    it "reports an expired token with its own error code" do
      expired = travel_to(2.hours.ago) { Auth::AccessToken.encode(account) }

      get "/probes/guarded", headers: bearer(expired)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("token_expired")
    end

    it "leaves endpoints marked open unauthenticated" do
      get "/probes/open"

      expect(response).to have_http_status(:ok)
    end
  end

  # research.md D10's accepted trade, asserted rather than assumed. If someone
  # later adds a per-request revocation check, this spec is the one that should
  # fail and force the decision back into the open.
  describe "the documented ban window" do
    it "does not load the account row to authenticate a request" do
      token = Auth::AccessToken.encode(account)

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] unless payload[:name] == "SCHEMA"
      end

      begin
        get "/probes/guarded", headers: bearer(token)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(queries).to be_empty
    end

    it "loads the row only for endpoints that ask for it" do
      get "/probes/guarded_with_record", headers: bearer(Auth::AccessToken.encode(account))

      expect(response.parsed_body["email"]).to eq(account.email)
    end

    it "honours an access token issued before the ban until it expires" do
      token = Auth::AccessToken.encode(account)
      account.update!(banned_at: Time.current)

      get "/probes/guarded", headers: bearer(token)

      expect(response).to have_http_status(:ok)
    end

    it "closes the window by revoking every refresh token the ban touches" do
      live = Auth::RefreshTokens.issue(account: account)

      account.update!(banned_at: Time.current)

      expect { Auth::RefreshTokens.rotate(live.token) }.to raise_error(Auth::RefreshTokens::Invalid)
    end
  end

  describe "error envelope" do
    it "reports a missing record as not_found without revealing what was looked up" do
      get "/probes/missing"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => { "code" => "not_found", "message" => "Not found" })
    end

    it "reports a validation failure with per-field details" do
      get "/probes/invalid"

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details")).to include("email")
    end
  end

  # FR-015 and Principle V. The cookie middleware is not in the stack at all, so
  # this holds for every path including the redirect — structurally, not by
  # anyone remembering.
  describe "cookies" do
    it "never sets one, authenticated or not" do
      get "/probes/open"
      expect(response.headers["set-cookie"]).to be_nil

      get "/probes/guarded", headers: bearer(Auth::AccessToken.encode(account))
      expect(response.headers["set-cookie"]).to be_nil
    end
  end

  # Principle I caps the redirect at one log line, and the cap is enforced
  # application-wide so it cannot rot on the paths nobody watches.
  describe "request logging" do
    def capture_log
      captured = StringIO.new
      original_logger = Rails.logger

      Rails.logger = ActiveSupport::Logger.new(captured)
      Rails.logger.level = Logger::DEBUG
      ActiveSupport::LogSubscriber.logger = Rails.logger

      begin
        yield
      ensure
        Rails.logger = original_logger
        ActiveSupport::LogSubscriber.logger = original_logger
      end

      captured.string.lines.reject { |line| line.strip.empty? }
    end

    it "emits exactly one structured line per request" do
      lines = capture_log { get "/probes/open" }

      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)).to include("event" => "request", "path" => "/probes/open", "status" => 200)
    end

    it "records nothing that identifies the client, and no credential" do
      token = Auth::AccessToken.encode(account)
      lines = capture_log { get "/probes/guarded", headers: bearer(token).merge("User-Agent" => "probe-agent") }

      expect(lines.first).not_to include(token)
      expect(JSON.parse(lines.first).keys).not_to include("ip", "remote_ip", "user_agent", "authorization")
    end
  end
end
