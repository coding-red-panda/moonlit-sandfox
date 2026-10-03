class CreateWorldOfWarcraftGuildRanks < ActiveRecord::Migration[8.1]
  def change
    create_table :world_of_warcraft_guild_ranks do |t|
      t.integer :rank, null: false
      t.string :name, null: false
      t.boolean :officer, null: false, default: false

      t.timestamps
    end

    add_index :world_of_warcraft_guild_ranks, :rank, unique: true
  end
end
