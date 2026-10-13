# frozen_string_literal: true

module Api
  module V1
    # `GET /api/v1/me` — who the caller is, according to the database.
    #
    # The dashboard needs an email to put in its header and a role to decide
    # whether to draw the admin link. Both were previously carried to the
    # browser in a readable cookie the BFF wrote at sign-in, which was wrong in
    # two ways: it put a person's address in a cookie that was attached to
    # requests having nothing to do with it, and it froze the answer at the
    # moment of sign-in, so a role granted or an address corrected did not
    # appear until the session was closed and opened again.
    #
    # This is the one place that question is answered, and it answers it from
    # the row.
    class AccountsController < BaseController
      def show
        render json: { account: AccountSerializer.call(current_account) }
      end
    end
  end
end
