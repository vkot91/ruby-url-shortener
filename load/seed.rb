# frozen_string_literal: true

# T040 — the fixed corpus the baseline and the cached run are both measured
# against (research.md D13, Principle II).
#
#   cd backend && bin/rails runner ../load/seed.rb
#
# Principle II only means something if the two runs differ in the code under
# test and in nothing else. That makes the corpus part of the instrument rather
# than part of the setup: same 10 000 links, same codes, same access ranks, both
# times. Everything here is therefore derived from one seed, and re-running the
# script reproduces the identical corpus rather than a fresh random one.
#
# It writes `load/corpus.json` because the k6 script cannot reach Postgres. That
# file is the contract between the two halves of the harness, and it is
# committed for the same reason the results are: a corpus nobody can reproduce
# turns the comparison into an anecdote.

SEED = Integer(ENV.fetch("LOAD_SEED", "20260901"))
CORPUS_SIZE = Integer(ENV.fetch("LOAD_CORPUS_SIZE", "10000"))
ACCOUNT_EMAIL = "load@snip.test"
ACCOUNT_PASSWORD = "load test password"

# Destinations are this pattern filled with the link's rank. Storing the
# pattern rather than 10 000 URLs keeps corpus.json small enough to read in
# review, and lets the k6 script assert the *exact* destination behind every
# code it requests — SC-005's "zero incorrect destinations" is otherwise
# unmeasurable.
DESTINATION_PATTERN = "https://example.com/load/%d"

random = Random.new(SEED)

alphabet = Links::CodeGenerator::ALPHABET
reserved = Rails.application.config.x.reserved_codes

codes = Set.new

# Drawn from the seeded PRNG rather than from `CodeGenerator.generate`, which
# uses SecureRandom and is by design not reproducible. Same alphabet and same
# length, so the corpus looks to the read path exactly like production data.
while codes.size < CORPUS_SIZE
  candidate = Array.new(Links::CodeGenerator::LENGTH) { alphabet[random.rand(alphabet.size)] }.join

  codes << candidate unless reserved.include?(candidate.downcase)
end

codes = codes.to_a

account = Account.find_by(email: ACCOUNT_EMAIL) ||
  Account.create!(email: ACCOUNT_EMAIL, password: ACCOUNT_PASSWORD)

# Idempotent, and destructive only within this account: re-running the seed
# must leave one corpus behind, not two. The click rows go with it, because a
# baseline run leaves millions of them and the next run should not be reading a
# table still carrying the last one's writes.
Click.where(link_id: Link.where(account_id: account.id).select(:id)).delete_all
Link.where(account_id: account.id).delete_all

now = Time.current

rows = codes.each_with_index.map do |code, rank|
  {
    account_id: account.id,
    code: code,
    destination_url: format(DESTINATION_PATTERN, rank),
    name: "load #{rank}",
    created_at: now,
    updated_at: now
  }
end

rows.each_slice(1_000) { |slice| Link.insert_all!(slice) }

corpus_path = Rails.root.join("../load/corpus.json").cleanpath

corpus_path.write(JSON.pretty_generate(
  seed: SEED,
  size: codes.size,
  destination_pattern: DESTINATION_PATTERN,
  account_email: ACCOUNT_EMAIL,
  # Rank 0 is the hottest link. The k6 script's Zipf draw indexes straight into
  # this array, so the popularity ordering lives in the corpus file rather than
  # being reinvented on each side of the harness.
  codes: codes
))

puts "seeded #{codes.size} links for #{ACCOUNT_EMAIL} (seed #{SEED})"
puts "wrote #{corpus_path}"
