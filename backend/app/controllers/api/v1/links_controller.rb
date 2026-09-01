# frozen_string_literal: true

module Api
  module V1
    # FR-005 through FR-012. Only `create` exists in 3A; the list, fetch, edit,
    # and delete actions arrive with US2 and US3.
    class LinksController < BaseController
      # FR-004's second half. Per account rather than per origin, because the
      # limit is a property of the plan and not of where the request came from.
      #
      # Note what this does *not* touch: `GET /:code`. Redirect traffic is never
      # throttled, whatever this account does here (FR-019, Principle I) —
      # RedirectsController has no limiter and spec/requests/redirect_never_-
      # throttled_spec.rb is what keeps it that way.
      rate_limit to: 30,
                 within: RateLimiting::WINDOW,
                 by: -> { current_account_id },
                 with: -> { render_rate_limited },
                 store: RATE_LIMIT_STORE,
                 only: :create

      def create
        link = Links::Creator.call(
          account: current_account,
          destination_url: params.require(:destination_url),
          name: params[:name]
        )

        render json: serialize(link), status: :created
      rescue Links::Rejection => rejection
        # One rescue for all six reasons. The reason travels as `error.code`,
        # which is what the create form branches on to put the message beside
        # the right field (design.md §6.4, P5).
        render_error(code: rejection.code, message: rejection.message, status: :unprocessable_content)
      end

      private

      # Inline for now. T062 extracts this into a serializer, once US2 gives it
      # a second caller; extracting it here would be a class with one call site
      # and a spec asserting it returns its own arguments.
      def serialize(link)
        {
          id: link.id,
          code: link.code,
          short_url: "https://#{Rails.application.config.x.short_domain}/#{link.code}",
          destination_url: link.destination_url,
          name: link.name,
          clicks_count: link.clicks_count,
          created_at: link.created_at.iso8601
        }
      end
    end
  end
end
