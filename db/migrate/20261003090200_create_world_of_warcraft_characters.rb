class CreateWorldOfWarcraftCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :world_of_warcraft_characters do |t|
      add_owners(t)
      add_attributes(t)

      t.timestamps
    end

    add_lookup_indexes
  end

  private

  # The index names are spelled out because the generated ones run past the
  # 63-character identifier limit Postgres silently truncates at.
  def add_owners(table)
    table.references :world_of_warcraft_account,
                     null: false, foreign_key: true,
                     index: { name: 'index_wow_characters_on_wow_account_id' }
    # Nullable on purpose: a character outside the guild, or on another realm,
    # has no rank to hold. Blizzard exposes ranks only through the guild roster.
    table.references :world_of_warcraft_guild_rank,
                     foreign_key: true,
                     index: { name: 'index_wow_characters_on_wow_guild_rank_id' }
  end

  def add_attributes(table)
    table.bigint :battle_net_character_id, null: false
    table.string :name, null: false
    table.string :realm_slug, null: false
    table.string :character_class, null: false
    table.integer :level, null: false
  end

  def add_lookup_indexes
    add_index :world_of_warcraft_characters, :battle_net_character_id,
              unique: true, name: 'index_wow_characters_on_battle_net_character_id'
    add_index :world_of_warcraft_characters, %i[realm_slug name],
              unique: true, name: 'index_wow_characters_on_realm_slug_and_name'
  end
end
