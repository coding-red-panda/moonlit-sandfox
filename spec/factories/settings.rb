FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "example.key.#{n}" }
    value { 'example-value' }
  end
end
