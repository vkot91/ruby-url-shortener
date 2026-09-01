# frozen_string_literal: true

# Idempotent, and run automatically by `db:prepare` when the database is
# created. Re-run at any time with `bin/rails db:seed`.

# The account the Bruno collection signs in as (bruno/01 - Auth/Sign in).
#
# A fixed address and password, so signing in is one request rather than
# "register first, then sign in as whoever that made". The credentials are
# committed on purpose — they are a development fixture, not a secret, and the
# whole point is that they are the same on every machine and after every
# `db:reset`.
#
# Guarded rather than merely discouraged: an account with a published password
# is a back door, and a seed file is exactly the sort of thing that gets run
# against production once.
if Rails.env.production?
  warn "Skipping the manual-testing account: it must never exist in production."
else
  account = Account.find_or_initialize_by(email: "dev@snip.test")

  # Assigned every run rather than only on create, so a seed re-run is also the
  # way to recover the account after someone changes its password by hand.
  account.password = "development password"

  account.save!

  Rails.logger.info { "Seeded the manual-testing account: #{account.email}" }
end
