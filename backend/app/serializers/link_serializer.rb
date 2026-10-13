# frozen_string_literal: true

# The `Link` schema from contracts/openapi.yaml, in one place.
#
# Three actions render it — create, index, and show — and a fourth and fifth
# arrive with US3. A field that appears in one of them and not the others is a
# client branching on whether the link it holds came back from a POST or a GET,
# so the shape is defined once and every action calls this.
#
# `short_url` is built rather than stored. The short domain is deployment
# configuration (`SHORT_DOMAIN`), and a column holding it would be a copy of
# that configuration frozen at the moment each row was written — every link
# created before a domain change would keep advertising the old one.
#
# What is deliberately absent: `account_id`, `banned_at`, and `deleted_at`. They
# belong to `AdminLink`, which is a different schema for a different audience
# (FR-034, design.md P6). A creator-facing serializer that happened to carry
# them would make leaking them a matter of nobody noticing.
module LinkSerializer
  def self.call(link)
    {
      id: link.id,
      code: link.code,
      short_url: short_url(link.code),
      destination_url: link.destination_url,
      name: link.name,
      clicks_count: link.clicks_count,
      created_at: link.created_at.iso8601
    }
  end

  def self.collection(links)
    links.map { |link| call(link) }
  end

  def self.short_url(code)
    "https://#{Rails.application.config.x.short_domain}/#{code}"
  end
end
