# frozen_string_literal: true

require "rails_helper"

RSpec.describe Urls::SafetyValidator do
  def expect_rejection(url, code)
    expect { described_class.call(url) }
      .to raise_error(Links::Rejection) { |error| expect(error.code).to eq(code) }
  end

  describe "scheme" do
    it "accepts https and http" do
      expect(described_class.call("https://example.com/x")).to eq("https://example.com/x")
      expect(described_class.call("http://example.com/x")).to eq("http://example.com/x")
    end

    it "refuses ftp" do
      expect_rejection("ftp://example.com/x", "unsupported_scheme")
    end

    it "refuses data, which is how a payload gets smuggled through a redirector" do
      expect_rejection("data:text/html,<script>alert(1)</script>", "unsupported_scheme")
    end

    it "refuses file" do
      expect_rejection("file://localhost/etc/passwd", "unsupported_scheme")
    end
  end

  # D11's reason for existing. Each of these is a hostname the attacker
  # controls, resolving to somewhere they should not be able to reach — so the
  # rejection has to come from the address, never from the name.
  describe "addresses that are not on the public internet" do
    {
      "loopback" => "127.0.0.1",
      "loopback, written the long way" => "127.9.9.9",
      "IPv6 loopback" => "::1",
      "private 10/8" => "10.0.0.7",
      "private 172.16/12" => "172.20.1.1",
      "private 192.168/16" => "192.168.1.1",
      "link-local — the cloud metadata endpoint" => "169.254.169.254",
      "IPv6 link-local" => "fe80::1",
      "IPv6 unique local" => "fd00::1",
      "carrier-grade NAT" => "100.100.1.1",
      "the unspecified address" => "0.0.0.0",
      "multicast" => "224.0.0.1",
      "reserved" => "240.0.0.1"
    }.each do |description, address|
      it "refuses a host resolving to #{description}" do
        resolve_all_hosts_to(address)

        expect_rejection("https://totally-innocent.example/x", "private_address")
      end
    end

    it "refuses an IPv4 address smuggled inside an IPv6 one" do
      resolve_all_hosts_to("::ffff:127.0.0.1")

      expect_rejection("https://totally-innocent.example/x", "private_address")
    end

    # A hostname with one public and one loopback record is a rebinding attempt.
    # Accepting it because the public record happened to come back first would
    # be accepting it.
    it "refuses a host with one good address and one bad one" do
      resolve_all_hosts_to(HostResolution::PUBLIC_ADDRESS, "127.0.0.1")

      expect_rejection("https://totally-innocent.example/x", "private_address")
    end

    it "judges a literal address without consulting DNS at all" do
      allow(Urls::HostResolver).to receive(:addresses).and_call_original

      expect_rejection("https://127.0.0.1/x", "private_address")

      expect(Urls::HostResolver).not_to have_received(:addresses)
    end

    it "accepts a host that resolves only to public addresses" do
      resolve_all_hosts_to(HostResolution::PUBLIC_ADDRESS)

      expect(described_class.call("https://example.com/x")).to eq("https://example.com/x")
    end

    it "refuses a host that resolves to nothing, since nobody can reach it" do
      resolve_all_hosts_to

      expect_rejection("https://nx.example/x", "invalid_url")
    end
  end

  describe "our own short domain" do
    it "refuses a destination pointing back at it" do
      expect_rejection("https://snp.to/abc1234", "self_referential")
    end

    it "refuses a subdomain of it" do
      expect_rejection("https://go.snp.to/abc1234", "self_referential")
    end

    it "refuses it whatever the case, since a host is case-insensitive" do
      expect_rejection("https://SNP.TO/abc1234", "self_referential")
    end

    it "does not refuse a domain that merely ends with the same letters" do
      expect(described_class.call("https://notsnp.to/x")).to eq("https://notsnp.to/x")
    end
  end
end
