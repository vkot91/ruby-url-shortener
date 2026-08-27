# frozen_string_literal: true

# Both extensions back a column type or an index declared in the migrations that
# follow, so they are enabled in their own migration ahead of them rather than
# as a side effect of whichever table happens to be created first.
class EnableExtensions < ActiveRecord::Migration[8.0]
  def change
    enable_extension "citext"   # accounts.email, blocked_domains.domain
    enable_extension "pg_trgm"  # links.destination_url admin search (FR-030)
  end
end
