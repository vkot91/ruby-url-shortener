# frozen_string_literal: true

module Urls
  # FR-008: destinations are stored in a canonical form.
  #
  # Canonical here means "the same address written the same way", not "the
  # shortest address that still works". Every transformation below is one the
  # URL specification says preserves meaning:
  #
  #   - scheme and host are case-insensitive, so they are lowercased;
  #   - a trailing dot on a host names the same host, so it goes;
  #   - the default port for the scheme is redundant, so it goes;
  #   - an empty path means `/`;
  #   - an empty query or fragment is the same as none.
  #
  # Deliberately *not* done: sorting or removing query parameters, stripping
  # `utm_*`, collapsing a trailing slash on a non-empty path, or unescaping
  # percent-encoding. Each of those can change which page a destination
  # resolves to, and a shortener that silently sends a visitor somewhere other
  # than where the creator pointed it has failed at its only job. FR-011's
  # refusal to merge duplicate destinations means nothing is gained by
  # aggressive canonicalisation anyway.
  module Normalizer
    DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze

    # A bare `example.com/x` is what people paste out of a browser bar. Assuming
    # https rather than http means the guess errs towards the safer scheme.
    ASSUMED_SCHEME = "https"

    # A scheme is "present" when it is followed by `://`, or by a colon that is
    # not the start of a port number. The second half is what tells
    # `data:text/html,...` apart from `example.com:8080/x` — both are a run of
    # scheme characters followed by a colon, and only one of them has a scheme.
    SCHEME_PRESENT = %r{\A(?<scheme>[a-z][a-z0-9+.\-]*):(//|(?![0-9]))}i

    class << self
      # @return [String] the canonical form
      # @raise [Links::Rejection] with code `invalid_url`
      def call(raw_url)
        candidate = raw_url.to_s.strip

        reject("A destination address is required") if candidate.empty?

        scheme = candidate[SCHEME_PRESENT, :scheme]&.downcase

        # A destination on a scheme this service does not shorten leaves here
        # with only its scheme case-folded, for Urls::SafetyValidator to refuse
        # as `unsupported_scheme` — normalising a scheme this service does not
        # understand would be guessing, and the rejection is one step away.
        #
        # It has to leave *before* parsing rather than after. `data:text/html,
        # <script>alert(1)</script>` is a string URI.parse raises on, and
        # `mailto:someone@example.com` parses to a URI with no host, so both
        # would otherwise be rejected here as `invalid_url` and never reach the
        # validator at all — and the contract names a different code for a
        # malformed address than for a scheme we refuse to shorten.
        return "#{scheme}#{candidate[scheme.length..]}" if scheme && !DEFAULT_PORTS.key?(scheme)

        uri = parse(candidate)

        reject("That destination is not a valid web address") if uri.host.blank?

        uri.scheme = uri.scheme.downcase
        uri.host = canonical_host(uri.host)
        uri.port = nil if uri.port == DEFAULT_PORTS[uri.scheme]
        uri.path = "/" if uri.path.blank?
        uri.query = nil if uri.query == ""
        uri.fragment = nil if uri.fragment == ""

        uri.to_s
      end

      private

      def parse(candidate)
        # The scheme is added before parsing rather than after: `URI.parse`
        # reads `example.com/x` as a path, and a URI with no host cannot have
        # one assigned onto it afterwards without rebuilding the string anyway.
        candidate = "#{ASSUMED_SCHEME}://#{candidate}" unless candidate.match?(SCHEME_PRESENT)

        URI.parse(candidate)
      rescue URI::InvalidURIError
        reject("That destination is not a valid web address")
      end

      def canonical_host(host)
        host.downcase.delete_suffix(".")
      end

      def reject(message)
        raise Links::Rejection.new("invalid_url", message)
      end
    end
  end
end
