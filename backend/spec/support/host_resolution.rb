# frozen_string_literal: true

# Urls::SafetyValidator resolves DNS before accepting a destination (D11), which
# means every spec that creates a link would otherwise depend on a network round
# trip and on `example.com` continuing to resolve the way it does today. Neither
# is a thing this suite should be testing.
#
# So Urls::HostResolver — the one seam where a hostname becomes addresses — is
# stubbed for the whole suite, resolving every host to a single public address.
# The SSRF specs override it per example with the address they are about, which
# is what lets them exercise the real classification rules against a loopback or
# metadata address without arranging for one to exist.
module HostResolution
  # A real public address, from the range IANA has never assigned to anything
  # private. Nothing connects to it; it only has to survive the range checks.
  PUBLIC_ADDRESS = "93.184.216.34"

  def resolve_all_hosts_to(*ip_addresses)
    addresses = ip_addresses.map { |address| IPAddr.new(address) }

    allow(Urls::HostResolver).to receive(:addresses).and_return(addresses)
  end
end

RSpec.configure do |config|
  config.include HostResolution

  config.before { resolve_all_hosts_to(HostResolution::PUBLIC_ADDRESS) }
end
