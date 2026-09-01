# frozen_string_literal: true

module Links
  # The six ways link creation can be refused, each carrying the `error.code`
  # the API returns for it (contracts/openapi.yaml `/links` POST 422).
  #
  # One error class rather than a hierarchy of six. The controller's job is to
  # name the reason, not to branch on it, and a `rescue` list that has to stay
  # in step with a class hierarchy is a list that eventually misses a member and
  # turns a 422 into a 500.
  #
  # It lives under `Links` rather than under `Urls` because the concept is "this
  # link cannot be created", not "this URL is bad" — `link_limit_reached` is
  # nothing to do with a URL. The `Urls::` services raise it because refusing a
  # destination is the only thing they exist to do.
  class Rejection < StandardError
    CODES = %w[
      invalid_url
      unsupported_scheme
      private_address
      self_referential
      blocked_domain
      link_limit_reached
    ].freeze

    attr_reader :code

    def initialize(code, message)
      raise ArgumentError, "unknown rejection code: #{code.inspect}" unless CODES.include?(code)

      @code = code

      super(message)
    end
  end
end
