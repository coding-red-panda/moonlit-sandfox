# Matches an account's characters against the guild roster and stamps their ranks
# on them (ADR-003).
#
# Split out from FetchCharactersJob because it needs no user token: the roster is
# game data, reachable with the application's own client credentials. That also
# means it can be re-run at any time, long after the login that triggered it.
class SynchronizeGuildRanksJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(account)
    Services::GuildRankSynchronization.new(account: account).synchronize
  end
end
