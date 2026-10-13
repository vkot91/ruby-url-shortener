# frozen_string_literal: true

module Api
  module V1
    # FR-002 through FR-012. Create landed in 3A; the list and the single fetch
    # arrive with US2, and the edit and delete actions with US3.
    class LinksController < BaseController
      # The list's page size. `MAX_PER_PAGE` is the contract's maximum
      # (contracts/openapi.yaml) and it is a clamp rather than a validation: a
      # client asking for 500 links gets 100 of them, not a 422 it has to
      # special-case. Nothing about the request is ambiguous — it is asking for
      # more than the server is willing to send in one response, and the honest
      # answer is the page plus a `pagination` block saying so.
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      # FR-004's second half. Per account rather than per origin, because the
      # limit is a property of the plan and not of where the request came from.
      #
      # Note what this does *not* touch: `GET /:code`. Redirect traffic is never
      # throttled, whatever this account does here (FR-019, Principle I) —
      # RedirectsController has no limiter and spec/requests/redirect_never_-
      # throttled_spec.rb is what keeps it that way.
      #
      # `index` and `show` are unthrottled too, and that is not an oversight.
      # The dashboard polls the list every 30 seconds (T108, SC-009), so a limit
      # low enough to matter would break the feature it was protecting, and a
      # limit high enough not to would protect nothing.
      rate_limit to: 30,
                 within: RateLimiting::WINDOW,
                 by: -> { current_account_id },
                 with: -> { render_rate_limited },
                 store: RATE_LIMIT_STORE,
                 only: :create

      # FR-002, FR-023. Newest first, which is the order the dashboard table
      # renders and the order the partial index on
      # (account_id, created_at DESC) WHERE deleted_at IS NULL was built for.
      def index
        page_of_links = owned_links.order(created_at: :desc, id: :desc)
                                   .offset((page - 1) * per_page)
                                   .limit(per_page)

        render json: {
          links: LinkSerializer.collection(page_of_links),
          pagination: { page: page, per_page: per_page, total: owned_links.count }
        }
      end

      # Needed by the edit form (T080), which has to load a link it did not
      # create in the same page view.
      #
      # `find` against the owner-scoped relation, not `Link.find` followed by an
      # ownership check: the 404 for another account's link then falls out of
      # the query rather than out of a branch somebody has to remember to write.
      # ErrorHandling turns the RecordNotFound into the `not_found` envelope,
      # which is the same body a genuinely absent id produces — indistinguishable
      # by design (FR-002).
      def show
        render json: LinkSerializer.call(owned_links.find(params.expect(:id)))
      end

      def create
        link = Links::Creator.call(
          account: current_account,
          destination_url: params.require(:destination_url),
          name: params[:name]
        )

        render json: LinkSerializer.call(link), status: :created
      rescue Links::Rejection => rejection
        # One rescue for all six reasons. The reason travels as `error.code`,
        # which is what the create form branches on to put the message beside
        # the right field (design.md §6.4, P5).
        render_error(code: rejection.code, message: rejection.message, status: :unprocessable_content)
      end

      private

      # Every read in this controller starts here, so ownership is a property of
      # the relation rather than of each action. Scoped by the token's account
      # id and not by `current_account`, so listing a page of links still loads
      # no accounts row (research.md D10, driver 3).
      #
      # `.active` as well as the ownership scope: a soft-deleted link keeps its
      # statistics and its code (FR-028, FR-029) but stops being something its
      # creator can see or edit.
      def owned_links
        Link.active.where(account_id: current_account_id)
      end

      def page
        @page ||= [ params[:page].to_i, 1 ].max
      end

      # Anything that is not a positive integer is the default rather than an
      # error — `to_i` renders "abc" and "0" and a missing parameter all as
      # zero, and a dashboard that answered a stray query string with a 422
      # would be refusing to show somebody their own links over a typo.
      def per_page
        @per_page ||= begin
          requested = params[:per_page].to_i

          requested.positive? ? requested.clamp(1, MAX_PER_PAGE) : DEFAULT_PER_PAGE
        end
      end
    end
  end
end
