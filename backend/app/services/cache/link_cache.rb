# frozen_string_literal: true

module Cache
  # The read cache behind the redirect (T047, data-model.md "Redis").
  #
  # One key per code, holding everything the redirect decision needs: the
  # destination, the link's id (so the click can be buffered without a second
  # lookup), and the three flags that can turn a redirect into a 404 or a
  # warning page. Packed into one string because Principle I allows the hot path
  # exactly one Redis round trip — a hash of fields would be no slower to read,
  # but every additional key or field is another thing an invalidation has to
  # remember to delete.
  #
  # Nothing here is a source of truth. Every value in it is reconstructible from
  # Postgres, and an empty Redis is correct and merely slower.
  module LinkCache
    # 24 hours, refreshed on every read (D6). A fixed TTL from write time
    # expires a link exactly when it is most popular; refresh-on-read makes
    # eviction track actual coldness instead.
    TTL = 24.hours

    # The codes an account has cached, so banning the account can invalidate them
    # without SCANning the keyspace (D14). Written on the miss path only, so the
    # hot path stays at one GETEX.
    #
    # This structure is scheduled for removal and is kept only so the shape of
    # the mistake stays visible until Phase 6 takes it out. Its TTL is refreshed
    # by `write`, which runs on a miss; the `link:` key it names is refreshed by
    # `read`, which runs on every request. A code that never misses again
    # therefore outlives its own membership record, and the ban that would have
    # consulted this set finds it empty exactly for the links being read the most
    # — see the 2026-09-03 amendment to D14 in research.md. The ban reads the
    # account's codes from Postgres instead, which makes this set redundant.
    ACCOUNT_CODES_TTL = 24.hours

    # The unit the middleware decides on. `account_id` is carried for the write
    # side (the D14 set) and is deliberately not packed into the cached value:
    # no redirect needs it, and the hot path parses whatever is stored.
    Entry = Struct.new(:link_id, :destination_url, :banned, :deleted, :account_banned, :account_id,
                       keyword_init: true) do
      def banned? = banned
      def deleted? = deleted
      def account_banned? = account_banned

      # data-model.md's resolution order: deleted reads as gone (404) even when
      # the link is also banned, so `deleted?` is asked first by the caller and
      # this covers only the two that produce the warning page (FR-018).
      def blocked? = banned? || account_banned?
    end

    BANNED_FLAG = 1
    DELETED_FLAG = 2
    ACCOUNT_BANNED_FLAG = 4

    SEPARATOR = "|"

    def self.key(code) = "link:#{code}"

    def self.account_codes_key(account_id) = "account:#{account_id}:codes"

    # The whole of the hot path's Redis work: one `GETEX`, which fetches and
    # extends the TTL in a single round trip (D6). Returns the raw string rather
    # than an Entry because the caller has to ask NegativeCache about it first —
    # the sentinel lives under this same key and is not a packed value.
    def self.read(code)
      REDIS.with { |redis| redis.getex(key(code), ex: TTL.to_i) }
    end

    def self.write(code, entry)
      REDIS.with do |redis|
        redis.set(key(code), pack(entry), ex: TTL.to_i)

        # Not pipelined with the SET above: these two are independent, and
        # `MULTI` would buy atomicity nobody needs — a set membership without
        # its cached link costs one wasted DEL at ban time.
        redis.sadd(account_codes_key(entry.account_id), code)
        redis.expire(account_codes_key(entry.account_id), ACCOUNT_CODES_TTL.to_i)
      end
    end

    # Idempotent by construction, which is why invalidation deletes rather than
    # overwrites (D2): a delete cannot publish a half-updated value, and two
    # concurrent writers racing to delete the same key agree.
    def self.delete(code)
      REDIS.with { |redis| redis.del(key(code)) }
    end

    def self.pack(entry)
      flags = 0
      flags |= BANNED_FLAG if entry.banned
      flags |= DELETED_FLAG if entry.deleted
      flags |= ACCOUNT_BANNED_FLAG if entry.account_banned

      [ flags, entry.link_id, entry.destination_url ].join(SEPARATOR)
    end

    # Split into three, not into as many parts as there are separators: a
    # destination URL is allowed to contain the separator character and the
    # trailing part is the URL to the end of the string.
    def self.unpack(raw)
      flags, link_id, destination_url = raw.split(SEPARATOR, 3)
      flags = flags.to_i

      Entry.new(
        link_id: link_id,
        destination_url: destination_url,
        banned: flags.anybits?(BANNED_FLAG),
        deleted: flags.anybits?(DELETED_FLAG),
        account_banned: flags.anybits?(ACCOUNT_BANNED_FLAG)
      )
    end
  end
end
