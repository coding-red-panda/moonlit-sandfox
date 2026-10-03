FactoryBot.define do
  factory :world_of_warcraft_guild_rank, class: 'WorldOfWarcraft::GuildRank' do
    sequence(:rank) { |n| n }
    sequence(:name) { |n| "Rank #{n}" }
    officer { false }

    trait :officer do
      officer { true }
    end
  end
end
