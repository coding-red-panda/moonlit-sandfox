require 'rails_helper'

RSpec.describe WorldOfWarcraft::Account, type: :model do
  subject { build(:world_of_warcraft_account) }

  it { is_expected.to belong_to(:account).class_name('::Account') }
  it { is_expected.to validate_presence_of(:battle_net_account_id) }

  # The prefix is what keeps this off the top-level accounts table.
  it 'lives in its own table' do
    expect(described_class.table_name).to eq('world_of_warcraft_accounts')
  end

  it 'rejects a duplicate battle_net_account_id' do
    create(:world_of_warcraft_account, battle_net_account_id: 3_547_048)

    expect(build(:world_of_warcraft_account, battle_net_account_id: 3_547_048)).not_to be_valid
  end

  it 'takes its characters with it when destroyed' do
    wow_account = create(:world_of_warcraft_account)
    create(:world_of_warcraft_character, world_of_warcraft_account: wow_account)

    expect { wow_account.destroy }.to change(WorldOfWarcraft::Character, :count).by(-1)
  end
end
