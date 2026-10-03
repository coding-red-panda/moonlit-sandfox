module Services
  # Stamps the guild's ranks onto an account's characters (ADR-003).
  #
  # The profile endpoint says nothing about guild membership, so rank can only come
  # from the guild roster, matched to our characters on the Battle.net character id.
  # The roster is game data rather than account data, which is what lets this run in
  # a background job: it needs a client credentials token, not the user's.
  class GuildRankSynchronization
    REALM_SLUG_SETTING = 'guild.realm_slug'.freeze
    NAME_SLUG_SETTING = 'guild.name_slug'.freeze

    def initialize(account:, client: BattleNet::ApiClient.new)
      @account = account
      @client = client
    end

    # Never raises. A roster that cannot be read leaves the ranks as they were;
    # they are refreshed on the next login.
    def synchronize
      return false unless guild_configured?

      assign_ranks(roster_ranks)

      true
    rescue BattleNet::ApiClient::Error => e
      Rails.logger.error("Guild rank synchronization failed for account #{@account.id}: #{e.message}")

      false
    end

    private

    # Battle.net character id => rank integer, for every member of the guild.
    def roster_ranks
      roster = @client.authenticate_application
                      .guild_roster(realm_slug: realm_slug, name_slug: name_slug)

      Array(roster['members']).to_h do |member|
        [member.fetch('character').fetch('id'), member.fetch('rank')]
      end
    end

    # Characters absent from the roster have left the guild, or were never in it,
    # and are cleared rather than left holding a stale rank.
    def assign_ranks(ranks)
      @account.characters.find_each do |character|
        character.update!(
          world_of_warcraft_guild_rank: guild_rank(ranks[character.battle_net_character_id])
        )
      end
    end

    def guild_rank(rank)
      return nil if rank.nil?

      guild_ranks[rank] || unseeded_rank(rank)
    end

    def guild_ranks
      @guild_ranks ||= WorldOfWarcraft::GuildRank.all.index_by(&:rank)
    end

    # The ladder is seeded, not discovered, so a rank added in game shows up here
    # before anyone has given it a name. Leave the character rankless and say so.
    def unseeded_rank(rank)
      Rails.logger.warn("Guild rank #{rank} is not seeded; leaving the character rankless")

      nil
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
