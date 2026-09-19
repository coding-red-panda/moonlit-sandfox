class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :battle_net_id, null: false
      t.string :battletag, null: false
      t.datetime :last_login_at

      t.timestamps
    end

    add_index :accounts, :battle_net_id, unique: true
  end
end
