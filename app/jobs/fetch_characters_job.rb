# Pulls the signed-in player's World of Warcraft characters after the login
# request has finished (ADR-003).
#
# This is the one job that needs the user's own access token: /profile/user/wow
# is account data and a client credentials token will not reach it. The token
# arrives sealed in an encrypted envelope rather than in the clear, because the
# argument is serialised into the Solid Queue tables to get here.
class FetchCharactersJob < ApplicationJob
  # Active Job logs its arguments by default. One of ours is the envelope, and a
  # log file has no business holding even the ciphertext of a credential.
  self.log_arguments = false

  queue_as :default

  # An account deleted between enqueue and run has nothing left to synchronize.
  discard_on ActiveJob::DeserializationError

  # Battle.net being briefly unreachable is worth another go; the envelope lasts
  # 24 hours, so the retries have a live token to work with.
  retry_on BattleNet::ApiClient::Error, wait: :polynomially_longer, attempts: 3

  def perform(account, sealed_access_token)
    access_token = BattleNet::AccessToken.unseal(sealed_access_token)
    return report_expired_token(account) if access_token.nil?

    Services::CharacterSynchronization
      .new(account: account, profile: access_token.wow_profile)
      .synchronize

    SynchronizeGuildRanksJob.perform_later(account)
  end

  private

  # The token outlived neither its envelope nor Battle.net's own 24 hours. There
  # is nothing to retry with: the characters are refreshed on the next login.
  def report_expired_token(account)
    Rails.logger.warn(
      "Skipping character fetch for account #{account.id}: the access token has expired"
    )
  end
end
