FactoryBot.define do
  factory :world_of_warcraft_character, class: 'WorldOfWarcraft::Character' do
    world_of_warcraft_account
    sequence(:battle_net_character_id) { |n| 180_318_000 + n }
    sequence(:name) { |n| "Keento#{n}" }
    realm_slug { 'argent-dawn' }
    character_class { 'Warrior' }
    level { 90 }

    trait :in_guild do
      world_of_warcraft_guild_rank factory: :world_of_warcraft_guild_rank
    end
  end
end
