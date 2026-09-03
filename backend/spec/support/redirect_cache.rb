# frozen_string_literal: true

# Both redirect paths stay runnable (Principle II), so both are testable, and
# the flag that chooses between them is the one knob the suite turns.
#
# `REDIRECT_CACHE_ENABLED` is read out of the environment once at boot
# (config/application.rb) and consulted per request by RedirectMiddleware, which
# is what lets an example flip it without restarting anything. Tag an example
# group `:cached` to run it against the middleware; untagged, it runs against
# the naive controller, which is where the 3B baseline lives.
module RedirectCache
  # The click is buffered on the cached path and written synchronously on the
  # naive one. A spec that asserts on a counter wants the same thing in both
  # cases — every click recorded so far — so it says that, once, here.
  def deliver_clicks
    Clicks::FlushJob.new.perform
  end
end

RSpec.configure do |config|
  config.include RedirectCache

  # Every example, not only the tagged ones. The application's default became
  # true in 3C, so leaving untagged examples on the default would quietly move
  # the whole suite onto the middleware and leave the naive path — which
  # Principle II requires to keep working — covered by nothing.
  config.around do |example|
    previous = Rails.application.config.x.redirect_cache_enabled
    Rails.application.config.x.redirect_cache_enabled = example.metadata[:cached].present?

    begin
      example.run
    ensure
      Rails.application.config.x.redirect_cache_enabled = previous
    end
  end
end
