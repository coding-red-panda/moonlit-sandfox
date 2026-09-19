FactoryBot.define do
  factory :account do
    sequence(:battle_net_id) { |n| "1234567#{n}" }
    sequence(:battletag) { |n| "Moonlit##{1000 + n}" }
    last_login_at { Time.current }
  end
end
