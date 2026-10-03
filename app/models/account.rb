class Account < ApplicationRecord
  has_many :world_of_warcraft_accounts,
           class_name: 'WorldOfWarcraft::Account',
           inverse_of: :account,
           dependent: :destroy
  has_many :characters, through: :world_of_warcraft_accounts
  has_many :guild_ranks, through: :characters, source: :world_of_warcraft_guild_rank

  validates :battle_net_id, presence: true, uniqueness: true
  validates :battletag, presence: true

  # The best rank the player holds on any of their characters. Rank 0 is the Guild
  # Master, so the best rank is the lowest number. Nil until the roster job has run,
  # and for anyone with no character in the guild.
  #
  # This is for display. Nothing reads it to decide what anyone may do — that is
  # authorization, and it waits on an ADR of its own.
  def highest_guild_rank
    guild_ranks.order(:rank).first
  end

  # Creates or refreshes the local account for a set of Battle.net userinfo claims.
  # The `sub` claim is the stable account identifier; the battletag is display-only
  # and is re-read on every login because users can change it.
  def self.from_userinfo(claims)
    account = find_or_initialize_by(battle_net_id: claims.fetch('sub').to_s)
    account.battletag = claims.fetch('battletag')
    account.last_login_at = Time.current
    account.save!
    account
  end
end
