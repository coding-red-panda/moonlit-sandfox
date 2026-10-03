class CreateWorldOfWarcraftAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :world_of_warcraft_accounts do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :battle_net_account_id, null: false

      t.timestamps
    end

    add_index :world_of_warcraft_accounts, :battle_net_account_id, unique: true
  end
end
