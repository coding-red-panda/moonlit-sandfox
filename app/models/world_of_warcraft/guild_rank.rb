module WorldOfWarcraft
  # A rank within the guild. Blizzard exposes ranks as bare integers — 0 is the
  # Guild Master — with no names and no notion of who is an officer, so both are
  # ours to keep. Seeded by bin/rails db:seed.
  class GuildRank < ApplicationRecord
    has_many :characters, class_name: 'WorldOfWarcraft::Character',
                          foreign_key: :world_of_warcraft_guild_rank_id,
                          inverse_of: :world_of_warcraft_guild_rank, dependent: :nullify

    validates :rank, presence: true, uniqueness: true,
                     numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :name, presence: true
    validates :officer, inclusion: { in: [true, false] }
  end
end
