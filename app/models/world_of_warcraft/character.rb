module WorldOfWarcraft
  # One character on one realm. The guild rank is optional: characters outside the
  # guild, and characters on realms the guild does not sit on, have none.
  class Character < ApplicationRecord
    belongs_to :world_of_warcraft_account, class_name: 'WorldOfWarcraft::Account',
                                           inverse_of: :characters
    belongs_to :world_of_warcraft_guild_rank, class_name: 'WorldOfWarcraft::GuildRank',
                                              inverse_of: :characters, optional: true

    # Mains first: the highest level, then alphabetical among equals.
    scope :ordered_by_level, -> { order(level: :desc, name: :asc) }

    validates :battle_net_character_id, presence: true, uniqueness: true
    validates :name, presence: true, uniqueness: { scope: :realm_slug }
    validates :realm_slug, presence: true
    validates :character_class, presence: true
    validates :level, presence: true,
                      numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  end
end
