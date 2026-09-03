# frozen_string_literal: true

# The cache is real in these specs, so it has to be empty at the start of each
# one (config/initializers/redis.rb explains the database split). DatabaseCleaner
# does not reach Redis, and a key left behind by one example is a cache hit in
# the next — which is exactly the class of bug the cache specs exist to catch,
# arriving as a pass rather than as a failure.
RSpec.configure do |config|
  config.before do
    REDIS.with { |redis| redis.flushdb }
  end
end
