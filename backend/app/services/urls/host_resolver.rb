# frozen_string_literal: true

module Urls
  # The one place a hostname becomes a list of IP addresses.
  #
  # Split out of Urls::SafetyValidator so that the safety *rules* can be tested
  # against fixed addresses without a network round trip, and so the suite does
  # not silently depend on DNS being reachable and on `example.com` continuing
  # to resolve the way it does today. See spec/support/host_resolution.rb.
  module HostResolver
    # A hostname that resolves to nothing is not a destination anyone can reach,
    # and the caller treats an empty list as a rejection rather than as "no
    # private addresses found, carry on".
    def self.addresses(host)
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).filter_map { |addrinfo| parse_address(addrinfo.ip_address) }.uniq
    rescue SocketError
      []
    end

    # A link-local IPv6 address arrives carrying its interface scope
    # (`fe80::1%en0`), which IPAddr will not parse. Dropping the scope keeps the
    # address — which is precisely the kind the validator most needs to see.
    def self.parse_address(ip_address)
      IPAddr.new(ip_address.split("%").first)
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end
