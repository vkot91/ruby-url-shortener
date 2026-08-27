# frozen_string_literal: true

# Every JSON failure leaves the API in the shape of the `Error` schema in
# contracts/openapi.yaml: `{ "error": { "code", "message", "details" } }`.
# Clients branch on `code`, never on `message` — the message is for humans and
# is free to change.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
  end

  private

  def render_error(code:, message:, status:, details: nil)
    error = { code: code, message: message }
    error[:details] = details if details.present?

    render json: { error: error }, status: status
  end

  # Ownership failures land here too. Another account's link is reported as
  # absent rather than forbidden, so the API never confirms that a link exists
  # to someone not entitled to know it does (FR-002).
  def render_not_found(_exception = nil)
    render_error(code: "not_found", message: "Not found", status: :not_found)
  end

  def render_record_invalid(exception)
    render_error(
      code: "validation_failed",
      message: exception.record.errors.full_messages.to_sentence,
      status: :unprocessable_content,
      details: exception.record.errors.to_hash
    )
  end

  def render_parameter_missing(exception)
    render_error(
      code: "parameter_missing",
      message: "Missing required parameter: #{exception.param}",
      status: :unprocessable_content
    )
  end
end
