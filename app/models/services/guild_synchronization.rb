module Services
  # Pulls the World of Warcraft data for an account while its access token is still
  # live. Battle.net issues no usable refresh token, so the callback request is the
  # only chance we get (ADR-002).
  #
  # Matching characters against the roster, deriving the account's effective rank and
  # granting permissions is authorization: it is out of scope for ADR-002 and waits on
  # an ADR of its own. The shape of these responses is not settled either, so for now
  # both payloads are recorded to log/payloads for study and nothing is persisted.
  class GuildSynchronization
    REALM_SLUG_SETTING = 'guild.realm_slug'.freeze
    NAME_SLUG_SETTING = 'guild.name_slug'.freeze

    def initialize(account:, session:, recorder: PayloadRecorder)
      @account = account
      @session = session
      @recorder = recorder
    end

    # Never raises. A guild pull that fails must not cost the user their login —
    # identity is established without it, and the data is refreshed on the next one.
    def call
      @recorder.record('wow-profile', @session.wow_profile)
      @recorder.record('guild-roster', guild_roster) if guild_configured?

      true
    rescue BattleNet::Client::Error => e
      Rails.logger.error("Guild synchronization failed for account #{@account.id}: #{e.message}")

      false
    end

    private

    def guild_roster
      @session.guild_roster(realm_slug: realm_slug, name_slug: name_slug)
    end

    # The guild we match members against is an operational value, not a constant:
    # it lives in the settings table so it can be changed without a deploy.
    def guild_configured?
      return true if realm_slug.present? && name_slug.present?

      Rails.logger.warn(
        "Skipping guild roster: settings #{REALM_SLUG_SETTING} and #{NAME_SLUG_SETTING} are unset"
      )

      false
    end

    def realm_slug
      @realm_slug ||= Setting[REALM_SLUG_SETTING]
    end

    def name_slug
      @name_slug ||= Setting[NAME_SLUG_SETTING]
    end
  end
end
