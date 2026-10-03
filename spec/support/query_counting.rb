# Counting queries is how an N+1 gets caught: the assertion is not "this page is
# fast" but "adding rows does not add queries". Nothing in the Gemfile does this
# and it is a dozen lines, so it lives here rather than pulling in a gem.
module QueryCounting
  # Schema reads and the transaction wrapping the example are noise that would
  # swamp the number being asserted on.
  IGNORED_NAMES = %w[SCHEMA TRANSACTION].freeze

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      count += 1 unless IGNORED_NAMES.include?(payload[:name])
    end

    yield

    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

RSpec.configure do |config|
  config.include QueryCounting
end
