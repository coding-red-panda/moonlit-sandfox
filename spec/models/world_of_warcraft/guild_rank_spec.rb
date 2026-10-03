require 'rails_helper'

RSpec.describe WorldOfWarcraft::GuildRank, type: :model do
  subject { build(:world_of_warcraft_guild_rank) }

  it { is_expected.to validate_presence_of(:rank) }
  it { is_expected.to validate_presence_of(:name) }

  it 'rejects a duplicate rank' do
    create(:world_of_warcraft_guild_rank, rank: 0)

    expect(build(:world_of_warcraft_guild_rank, rank: 0)).not_to be_valid
  end

  it 'rejects a negative rank' do
    expect(build(:world_of_warcraft_guild_rank, rank: -1)).not_to be_valid
  end

  it 'is not an officer rank by default' do
    expect(described_class.new).not_to be_officer
  end

  # Ranks are deleted rarely, but a character must survive losing one.
  it 'releases its characters rather than destroying them' do
    rank = create(:world_of_warcraft_guild_rank)
    character = create(:world_of_warcraft_character, world_of_warcraft_guild_rank: rank)

    expect { rank.destroy }.to change { character.reload.world_of_warcraft_guild_rank }.to(nil)
  end
end
