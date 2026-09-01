# frozen_string_literal: true

module Links
  # The whole of link creation, in the order the rejections are cheapest to
  # establish: the account's own quota, then the shape of the address, then
  # whether it is an address we will shorten at all, then the platform
  # blocklist.
  #
  # Every refusal leaves by the same door — a Links::Rejection carrying the
  # `error.code` the contract names for it (FR-005 through FR-012).
  module Creator
    class << self
      def call(account:, destination_url:, name: nil)
        enforce_link_limit(account)

        normalized_url = Urls::Normalizer.call(destination_url)

        # Before the blocklist, not after. The normalizer hands a non-http(s)
        # destination onward untouched so that this validator can refuse it as
        # `unsupported_scheme`, which means a URL like `data:text/html,<x>`
        # reaches here still carrying characters `URI.parse` throws on — and
        # `enforce_blocklist` parses. Refusing the scheme first is what keeps
        # that from being a 500. The cost is a DNS lookup for a destination
        # that a blocklist hit would have refused anyway, which is a lookup we
        # were going to make for every accepted link regardless.
        Urls::SafetyValidator.call(normalized_url)

        enforce_blocklist(normalized_url)

        allocate_and_insert(account: account, destination_url: normalized_url, name: name.presence)
      end

      private

      # FR-004. Counted over links that have not been soft-deleted, so deleting
      # one frees the slot even though it never frees the code (D12).
      #
      # This is a check-then-write, and unlike code allocation it is left as
      # one. Two simultaneous creations at the boundary can produce a 51st link;
      # the cost of that is one extra row for one customer, and the cure — a
      # counter column with its own contention, or a constraint trigger on the
      # busiest write in the system — is worse than the disease. Principle III
      # is about invariants the product's correctness rests on, and "at most 50"
      # is a commercial limit, not an invariant.
      def enforce_link_limit(account)
        return if account.links.active.count < Account::FREE_LINK_LIMIT

        reject("link_limit_reached", "Free accounts are limited to #{Account::FREE_LINK_LIMIT} active links")
      end

      # FR-007. Matches the registrable domain and every subdomain of it, so
      # blocking `evil.com` also blocks `tracking.cdn.evil.com`. One query with
      # every candidate suffix rather than one query per suffix.
      def enforce_blocklist(url)
        host = URI.parse(url).hostname.to_s
        labels = host.split(".")
        candidates = (0...labels.size).map { |index| labels[index..].join(".") }

        return unless BlockedDomain.exists?(domain: candidates)

        reject("blocked_domain", "That destination's domain is not permitted on this platform")
      end

      # Insert and rescue. The unique index on `code` is the allocation
      # algorithm, not a safety net behind an application-level check (D3).
      def allocate_and_insert(account:, destination_url:, name:)
        CodeGenerator.allocate do |code|
          Link.create!(account: account, code: code, destination_url: destination_url, name: name)
        end
      end

      def reject(code, message)
        raise Rejection.new(code, message)
      end
    end
  end
end
