# frozen_string_literal: true

# The `Account` schema from contracts/openapi.yaml, in one place.
#
# Deliberately not the row. `password_digest` is the obvious exclusion, but the
# one that matters more is `banned_at`: whether an account is banned is an
# administrative fact about it, and `GET /me` answering with it would tell a
# banned creator exactly what had happened to them and when. A banned account
# cannot reach this endpoint at all — its refresh tokens were revoked by the
# ban and its access token dies within fifteen minutes — so the field would be
# permanently absent in every response that could carry it anyway.
#
# `role` is here because the dashboard branches on it to draw the admin link,
# and for no stronger reason than that: it is display, not authorisation. Rails
# reads the role from the signed token on every request (Authentication), so a
# client that lied to itself about this value reaches endpoints that 403.
module AccountSerializer
  def self.call(account)
    {
      id: account.id,
      email: account.email,
      role: account.role,
      plan: account.plan,
      created_at: account.created_at.iso8601
    }
  end
end
