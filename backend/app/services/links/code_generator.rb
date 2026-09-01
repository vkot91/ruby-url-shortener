# frozen_string_literal: true

module Links
  # FR-009, FR-010, FR-012 and research.md D3.
  #
  # Codes are 7 characters drawn from a 62-character alphabet by a CSPRNG.
  # Random rather than a sequence encoded to base62: a sequence is shorter and
  # never collides, but it also makes the entire corpus walkable from outside,
  # which is a privacy failure for every customer who assumed an unlisted link
  # was unlisted.
  #
  # Uniqueness is the unique index's job, and `allocate` is where that shows.
  # There is no `Link.exists?(code:)` anywhere in this file or in its caller —
  # a SELECT followed by an INSERT has a window in it that concurrency will
  # eventually find, and 62^7 ≈ 3.5×10^12 makes the retry path so nearly dead
  # that correctness here costs nothing (Principle III).
  module CodeGenerator
    ALPHABET = [ ("0".."9"), ("a".."z"), ("A".."Z") ].flat_map(&:to_a).freeze
    LENGTH = 7

    # Five is not a tuning parameter. At MVP scale the first attempt collides
    # roughly never; the bound exists so that a genuine unique-violation from
    # some *other* column cannot spin forever disguised as a code collision.
    MAX_ATTEMPTS = 5

    class << self
      # Yields a fresh candidate code to a block that performs the insert, and
      # retries with a new one when the store rejects it as taken.
      def allocate
        attempts = 0

        begin
          attempts += 1

          yield generate
        rescue ActiveRecord::RecordNotUnique
          retry if attempts < MAX_ATTEMPTS

          raise
        end
      end

      def generate
        # `SecureRandom.random_number` over the alphabet size rather than
        # `SecureRandom.alphanumeric`: the latter is a fine generator, but
        # spelling the alphabet out is what makes FR-009's "letters and digits"
        # checkable against this file.
        loop do
          code = Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join

          return code unless reserved?(code)
        end
      end

      private

      # FR-012. `favicon`, `sitemap`, and `signup` are all reachable by a
      # 7-character draw, and a code the router swallows is a code that never
      # redirects. Case-insensitive because codes are `[A-Za-z0-9]` and `Admin`
      # collides with the same route `admin` does.
      def reserved?(code)
        Rails.application.config.x.reserved_codes.include?(code.downcase)
      end
    end
  end
end
