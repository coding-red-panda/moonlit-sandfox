module Services
  # Turns a /profile/user/wow payload into World of Warcraft accounts and
  # characters (ADR-003).
  #
  # The payload is the whole truth about what the player owns, so this is a
  # reconciliation rather than an import: characters that have appeared are
  # created, characters that have gone are destroyed, and the rest have their
  # level and class brought up to date.
  #
  # Guild rank is deliberately not touched here. The profile endpoint does not
  # report guild membership at all — only the roster does — so ranks are
  # Services::GuildRankSynchronization's business.
  class CharacterSynchronization
    def initialize(account:, profile:)
      @account = account
      @profile = profile
    end

    # Returns the World of Warcraft accounts the payload described.
    def synchronize
      accounts = Array(@profile['wow_accounts']).map { |payload| synchronize_account(payload) }
      discard_accounts_missing_from(accounts)

      accounts
    end

    private

    def synchronize_account(payload)
      account = WorldOfWarcraft::Account
                .find_or_initialize_by(battle_net_account_id: payload.fetch('id'))
      account.update!(account: @account)
      synchronize_characters(account, Array(payload['characters']))

      account
    end

    def synchronize_characters(account, payloads)
      characters = payloads.map { |payload| synchronize_character(account, payload) }
      account.characters.where.not(id: characters.map(&:id)).destroy_all
    end

    # Keyed on the Battle.net character id rather than name and realm, so a rename
    # or a realm transfer updates the character instead of orphaning it.
    def synchronize_character(account, payload)
      character = WorldOfWarcraft::Character
                  .find_or_initialize_by(battle_net_character_id: payload.fetch('id'))
      character.update!(
        world_of_warcraft_account: account,
        name: payload.fetch('name'),
        realm_slug: payload.fetch('realm').fetch('slug'),
        character_class: payload.fetch('playable_class').fetch('name'),
        level: payload.fetch('level')
      )

      character
    end

    # A whole game account can be closed or unlinked; its characters go with it.
    def discard_accounts_missing_from(accounts)
      @account.world_of_warcraft_accounts.where.not(id: accounts.map(&:id)).destroy_all
    end
  end
end
