FactoryBot.define do
  factory :world_of_warcraft_account, class: 'WorldOfWarcraft::Account' do
    account
    sequence(:battle_net_account_id) { |n| 3_547_000 + n }
  end
end
