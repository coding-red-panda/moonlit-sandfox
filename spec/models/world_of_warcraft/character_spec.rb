require 'rails_helper'

RSpec.describe WorldOfWarcraft::Character, type: :model do
  subject { build(:world_of_warcraft_character) }

  it { is_expected.to belong_to(:world_of_warcraft_account) }
  it { is_expected.to validate_presence_of(:battle_net_character_id) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:realm_slug) }
  it { is_expected.to validate_presence_of(:character_class) }
  it { is_expected.to validate_presence_of(:level) }

  # Characters outside the guild, and characters on other realms, have no rank:
  # Blizzard only hands ranks out through the guild roster.
  it { is_expected.to belong_to(:world_of_warcraft_guild_rank).optional }

  it 'rejects a duplicate character id' do
    create(:world_of_warcraft_character, battle_net_character_id: 180_318_917)

    expect(build(:world_of_warcraft_character, battle_net_character_id: 180_318_917))
      .not_to be_valid
  end

  it 'rejects a duplicate name on the same realm' do
    create(:world_of_warcraft_character, name: 'Keento', realm_slug: 'argent-dawn')

    expect(build(:world_of_warcraft_character, name: 'Keento', realm_slug: 'argent-dawn'))
      .not_to be_valid
  end

  it 'allows the same name on a different realm' do
    create(:world_of_warcraft_character, name: 'Keento', realm_slug: 'argent-dawn')

    expect(build(:world_of_warcraft_character, name: 'Keento', realm_slug: 'sunstrider'))
      .to be_valid
  end
end
