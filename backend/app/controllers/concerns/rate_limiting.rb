# frozen_string_literal: true

# Shared plumbing for Rails' `rate_limit`: where the counters live, and how a
# request is identified without keeping anything that identifies a person.
#
# FR-036 and FR-004 are the requirements; Principle V is why the keys look the
# way they do.
module RateLimiting
  extend ActiveSupport::Concern

  # The limiter's own window. One hour throughout, because every limit the spec
  # states is stated per hour and a second period would be a second thing to
  # reason about at 3am.
  WINDOW = 1.hour

  private

  # Keyed, not merely hashed.
  #
  # The IPv4 space is 4.3 billion addresses, which is a few seconds of work to
  # enumerate — so a bare SHA-256 of an address is a reversible identifier
  # wearing a costume, and a limiter key holding one is a limiter key holding an
  # IP address. An HMAC under a key the attacker does not have is not
  # reversible, and the key is derived from `secret_key_base` so there is
  # nothing extra to configure or rotate.
  def rate_limit_key(scope, value)
    "#{scope}:#{OpenSSL::HMAC.hexdigest('SHA256', RateLimiting.secret, value.to_s)}"
  end

  def hashed_ip = rate_limit_key("ip", request.remote_ip)

  # Downcased before hashing. `A@example.com` and `a@example.com` are the same
  # account — `email` is citext — so they must share one counter, or the
  # per-address limit is bypassed by pressing shift (FR-036).
  def hashed_email(email) = rate_limit_key("email", email.to_s.downcase)

  # The default `with:` — a 429 in the API's own error envelope rather than
  # Rails' bare `head :too_many_requests`, so a client parses this refusal the
  # same way it parses every other one.
  def render_rate_limited
    render_error(
      code: "rate_limited",
      message: "Too many requests. Try again later.",
      status: :too_many_requests
    )
  end

  def self.secret
    @secret ||= Rails.application.key_generator.generate_key("rate_limiting", 32)
  end
end
