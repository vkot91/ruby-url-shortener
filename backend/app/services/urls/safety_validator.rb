# frozen_string_literal: true

module Urls
  # FR-006, research.md D11. Refuses a destination that is not a public web
  # address, in the four ways the requirement names.
  #
  # The load-bearing decision is that this resolves DNS rather than inspecting
  # the hostname string. A denylist of hostnames is defeated by anyone who
  # points an A record at `169.254.169.254` — which costs an attacker one DNS
  # record and buys them a shortener that will probe a cloud metadata service on
  # request. Resolving first and judging the addresses closes that.
  #
  # **Accepted residual risk (D11)**: DNS can change between this check and the
  # visitor's click. A redirector cannot close that window, because the fetch
  # happens in the visitor's browser and not here. Recorded rather than solved.
  #
  # Re-run on destination edit as well as on creation (T074) — a validation that
  # only guards the first write is a validation with an obvious way around it.
  module SafetyValidator
    PERMITTED_SCHEMES = %w[http https].freeze

    # Everything that is not a public unicast address. `IPAddr`'s own
    # `private?`, `loopback?`, and `link_local?` predicates cover the famous
    # three and nothing else, so the rest are spelled out: carrier-grade NAT and
    # the IETF/benchmark/documentation blocks are all reachable from inside a
    # datacentre and none of them is a place a customer's link should point.
    BLOCKED_RANGES = [
      "0.0.0.0/8",          # "this network"
      "10.0.0.0/8",         # private
      "100.64.0.0/10",      # carrier-grade NAT
      "127.0.0.0/8",        # loopback
      "169.254.0.0/16",     # link-local — the cloud metadata endpoint lives here
      "172.16.0.0/12",      # private
      "192.0.0.0/24",       # IETF protocol assignments
      "192.0.2.0/24",       # TEST-NET-1
      "192.168.0.0/16",     # private
      "198.18.0.0/15",      # benchmarking
      "198.51.100.0/24",    # TEST-NET-2
      "203.0.113.0/24",     # TEST-NET-3
      "224.0.0.0/4",        # multicast
      "240.0.0.0/4",        # reserved, including the broadcast address
      "::/128",             # unspecified
      "::1/128",            # loopback
      "64:ff9b::/96",       # NAT64
      "100::/64",           # discard-only
      "2001:db8::/32",      # documentation
      "fc00::/7",           # unique local
      "fe80::/10",          # link-local
      "ff00::/8"            # multicast
    ].map { |range| IPAddr.new(range) }.freeze

    class << self
      # @param url [String] a normalised destination (Urls::Normalizer output)
      # @return [String] the same URL, having survived every check
      # @raise [Links::Rejection] `unsupported_scheme`, `self_referential`,
      #   `private_address`, or `invalid_url`
      def call(url)
        # The scheme is read off the string before the URL is parsed, not after.
        # `data:text/html,<script>...` is a scheme this service must refuse, and
        # it is also a string `URI.parse` throws on — parse first and the
        # rejection arrives as `invalid_url`, which tells the creator to check
        # for a typo in an address that has no typo in it.
        reject("unsupported_scheme", "Only http and https destinations are supported") unless permitted_scheme?(url)

        uri = URI.parse(url)

        # Downcased here as well as in the normalizer. This service is also
        # called on its own when a destination is edited (T074), and a check
        # that only holds because something upstream happened to run first is a
        # check with a way around it.
        host = uri.hostname.to_s.downcase

        reject("invalid_url", "That destination is not a valid web address") if host.empty?
        reject("self_referential", "A short link cannot point at another short link") if self_referential?(host)

        addresses = addresses_for(host)

        reject("invalid_url", "That destination's domain could not be resolved") if addresses.empty?

        # Every address, not the first. A hostname with one public and one
        # loopback A record is a rebinding attempt, and accepting it because the
        # public one happened to sort first would be accepting it.
        reject("private_address", "That destination resolves to a private address") if addresses.any? { |address| blocked?(address) }

        url
      rescue URI::InvalidURIError
        reject("invalid_url", "That destination is not a valid web address")
      end

      private

      def permitted_scheme?(url)
        scheme = url[%r{\A([a-z][a-z0-9+.\-]*)://}i, 1]

        PERMITTED_SCHEMES.include?(scheme&.downcase)
      end

      # FR-006's "points back at the service's own short-link space". Shortening
      # our own codes builds redirect chains that cost a visitor two round trips
      # and can be looped into a cycle.
      def self_referential?(host)
        short_domain = Rails.application.config.x.short_domain.downcase

        host == short_domain || host.end_with?(".#{short_domain}")
      end

      # A literal address is judged directly. Handing `127.0.0.1` to a resolver
      # would work, but it would make a check that needs no network depend on
      # one.
      def addresses_for(host)
        literal = HostResolver.parse_address(host) if host.match?(/\A[\[\]0-9a-fA-F:.]+\z/)

        return [ literal ] if literal

        HostResolver.addresses(host)
      end

      def blocked?(address)
        # An IPv4 address written as `::ffff:127.0.0.1` is the same address, and
        # would otherwise miss every IPv4 range below.
        address = address.native if address.ipv4_mapped?

        BLOCKED_RANGES.any? { |range| range.include?(address) }
      end

      def reject(code, message)
        raise Links::Rejection.new(code, message)
      end
    end
  end
end
