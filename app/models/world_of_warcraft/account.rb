module WorldOfWarcraft
  # One World of Warcraft game account. A single Battle.net account can hold
  # several of them, each with its own characters.
  class Account < ApplicationRecord
    belongs_to :account, class_name: '::Account', inverse_of: :world_of_warcraft_accounts
    has_many :characters, class_name: 'WorldOfWarcraft::Character',
                          foreign_key: :world_of_warcraft_account_id,
                          inverse_of: :world_of_warcraft_account, dependent: :destroy

    validates :battle_net_account_id, presence: true, uniqueness: true
  end
end
