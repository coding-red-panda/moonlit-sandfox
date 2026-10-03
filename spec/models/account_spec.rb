require 'rails_helper'

RSpec.describe Account, type: :model do
  subject { build(:account) }

  it { is_expected.to validate_presence_of(:battle_net_id) }
  it { is_expected.to validate_presence_of(:battletag) }
  it { is_expected.to have_many(:world_of_warcraft_accounts).class_name('WorldOfWarcraft::Account') }
  it { is_expected.to have_many(:characters).through(:world_of_warcraft_accounts) }

  it 'rejects a duplicate battle_net_id' do
    create(:account, battle_net_id: '123456789')

    expect(build(:account, battle_net_id: '123456789')).not_to be_valid
  end

  describe '#highest_guild_rank' do
    subject(:account) { create(:account) }

    let(:wow_account) { create(:world_of_warcraft_account, account: account) }

    def character_ranked(rank)
      create(:world_of_warcraft_character, world_of_warcraft_account: wow_account,
                                           world_of_warcraft_guild_rank: rank)
    end

    it 'is nil before the roster job has run' do
      create(:world_of_warcraft_character, world_of_warcraft_account: wow_account)

      expect(account.highest_guild_rank).to be_nil
    end

    # Rank 0 is the Guild Master, so the best rank is the lowest number.
    it 'is the lowest rank number held on any character' do
      character_ranked(create(:world_of_warcraft_guild_rank, rank: 7, name: 'Caravan Friend'))
      character_ranked(create(:world_of_warcraft_guild_rank, rank: 1, name: 'Council'))

      expect(account.highest_guild_rank.name).to eq('Council')
    end

    it 'ignores the ranks of other accounts' do
      create(:world_of_warcraft_character,
             world_of_warcraft_guild_rank: create(:world_of_warcraft_guild_rank, rank: 0))

      expect(account.highest_guild_rank).to be_nil
    end
  end

  describe '.from_userinfo' do
    let(:claims) { { 'sub' => '987654321', 'battletag' => 'Sandfox#2145' } }

    it 'creates an account keyed on the sub claim', :aggregate_failures do
      expect { described_class.from_userinfo(claims) }.to change(described_class, :count).by(1)

      expect(described_class.last).to have_attributes(
        battle_net_id: '987654321',
        battletag: 'Sandfox#2145'
      )
    end

    it 'coerces a numeric sub to a string' do
      account = described_class.from_userinfo(claims.merge('sub' => 987_654_321))

      expect(account.battle_net_id).to eq('987654321')
    end

    it 'records the login time' do
      freeze_time do
        expect(described_class.from_userinfo(claims).last_login_at).to eq(Time.current)
      end
    end

    it 'reuses the existing account when the battletag has been renamed', :aggregate_failures do
      existing = create(:account, battle_net_id: '987654321', battletag: 'OldName#1111')

      expect { described_class.from_userinfo(claims) }.not_to change(described_class, :count)
      expect(existing.reload.battletag).to eq('Sandfox#2145')
    end

    it 'raises when a required claim is absent' do
      expect { described_class.from_userinfo('sub' => '1') }.to raise_error(KeyError)
    end
  end
end
