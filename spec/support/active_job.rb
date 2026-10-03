# The test adapter collects jobs rather than running them, which is what lets a
# spec assert that a login enqueued the character fetch instead of performing it.
#
# ActiveJob::TestHelper normally clears that collection from Minitest's setup
# hooks, which RSpec never calls, so an un-cleared queue would leak jobs from one
# example into the next.
RSpec.configure do |config|
  config.include ActiveJob::TestHelper

  config.before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
end
