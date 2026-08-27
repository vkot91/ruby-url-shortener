# frozen_string_literal: true

# One structured line per request, and exactly one.
#
# Principle I caps the redirect path at a single log line, and a cap that only
# applies to one path is a cap nobody maintains — so the whole application logs
# the same way. Rails' default emits three to five lines per request ("Started",
# "Processing", "Parameters", "Completed"); those subscribers are detached
# rather than supplemented, because leaving them attached would mean the cap is
# only met by the middleware that bypasses them.
#
# Note what is absent: no remote IP, no user agent, no query string. The
# redirect path is anonymous and stays that way in the logs too (FR-024,
# Principle V); an IP written to a log file is an IP the product stores.

# Referenced by name below. Zeitwerk does not autoload framework internals, and
# in an API-only app nothing else has pulled this file in by initializer time.
require "action_controller/log_subscriber"
require "action_view/log_subscriber"

class StructuredRequestLogSubscriber < ActiveSupport::LogSubscriber
  def process_action(event)
    payload = event.payload

    line = {
      event: "request",
      method: payload[:method],
      path: payload[:path]&.split("?")&.first,
      controller: payload[:controller],
      action: payload[:action],
      status: status_for(payload),
      duration_ms: event.duration.round(2),
      db_ms: payload[:db_runtime]&.round(2),
      request_id: payload[:request]&.request_id
    }.compact

    info(JSON.generate(line))
  end

  private

  def status_for(payload)
    return payload[:status] if payload[:status]
    return ActionDispatch::ExceptionWrapper.status_code_for_exception(payload[:exception].first) if payload[:exception]

    0
  end
end

Rails.application.configure do
  # Removes the "Started GET ..." line, which is emitted by middleware and so is
  # not covered by detaching the controller subscriber below.
  config.middleware.delete(Rails::Rack::Logger)
end

ActionController::LogSubscriber.detach_from :action_controller

# The short domain's not-found and safety-warning pages are ERB, and view
# rendering logs further lines of its own. Detached for the same reason.
#
# `detach_from` alone is not enough here: ActionView::LogSubscriber.attach_to
# also registers two standalone `Start` listeners that emit the "Rendering ..."
# lines, and detaching the subscriber leaves those subscribed. They silence
# themselves above debug level, so this only shows up in development and test —
# which is exactly where someone would check whether the cap holds.
ActionView::LogSubscriber.detach_from :action_view
ActiveSupport::Notifications.unsubscribe("render_template.action_view")
ActiveSupport::Notifications.unsubscribe("render_layout.action_view")

StructuredRequestLogSubscriber.attach_to :action_controller
