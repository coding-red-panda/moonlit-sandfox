require 'rails_helper'

RSpec.describe Services::CharacterSynchronization, type: :model do
  subject(:synchronization) { described_class.new(account: account, profile: profile) }

  let(:account) { create(:account) }

  # Trimmed from a real /profile/user/wow response: two game accounts on one
  # Battle.net account, which is the case the ADR calls out.
  let(:profile) do
    {
      'id' => 316_649,
      'wow_accounts' => [
        { 'id' => 3_547_048, 'characters' => [character_payload] },
        { 'id' => 22_001_872, 'characters' => [] }
      ]
    }
  end

  let(:character_payload) do
    {
      'id' => 180_318_917,
      'name' => 'Keento',
      'level' => 90,
      'realm' => { 'id' => 536, 'name' => 'Argent Dawn', 'slug' => 'argent-dawn' },
      'playable_class' => { 'id' => 1, 'name' => 'Warrior' }
    }
  end

  it 'creates a record for every game account' do
    expect { synchronization.synchronize }
      .to change { account.world_of_warcraft_accounts.count }.by(2)
  end

  describe 'the characters it creates' do
    subject(:character) { WorldOfWarcraft::Character.sole }

    before { synchronization.synchronize }

    it 'files them under the game account that owns them' do
      expect(character.world_of_warcraft_account.battle_net_account_id).to eq(3_547_048)
    end

    it 'copies across the name, realm, class and level' do
      expect(character).to have_attributes(
        battle_net_character_id: 180_318_917, name: 'Keento',
        realm_slug: 'argent-dawn', character_class: 'Warrior', level: 90
      )
    end
  end

  it 'leaves the guild rank alone, because the profile does not report one' do
    synchronization.synchronize

    expect(WorldOfWarcraft::Character.sole.world_of_warcraft_guild_rank).to be_nil
  end

  it 'is safe to run twice over the same payload' do
    synchronization.synchronize

    expect { described_class.new(account: account, profile: profile).synchronize }
      .not_to change(WorldOfWarcraft::Character, :count)
  end

  describe 'reconciling against what is already stored' do
    before { synchronization.synchronize }

    it 'updates a level that has moved on' do
      character_payload['level'] = 92
      described_class.new(account: account, profile: profile).synchronize

      expect(WorldOfWarcraft::Character.sole.level).to eq(92)
    end

    # Keyed on the Battle.net id, so this is a rename rather than a new character.
    it 'follows a rename instead of orphaning the character', :aggregate_failures do
      character_payload['name'] = 'Keerin'
      described_class.new(account: account, profile: profile).synchronize

      expect(WorldOfWarcraft::Character.count).to eq(1)
      expect(WorldOfWarcraft::Character.sole.name).to eq('Keerin')
    end

    it 'destroys a character that has left the payload' do
      profile['wow_accounts'].first['characters'] = []

      expect { described_class.new(account: account, profile: profile).synchronize }
        .to change(WorldOfWarcraft::Character, :count).by(-1)
    end

    it 'destroys a game account that has left the payload' do
      profile['wow_accounts'].pop

      expect { described_class.new(account: account, profile: profile).synchronize }
        .to change { account.world_of_warcraft_accounts.count }.by(-1)
    end

    it 'takes the characters of a departed game account with it' do
      profile['wow_accounts'].shift

      expect { described_class.new(account: account, profile: profile).synchronize }
        .to change(WorldOfWarcraft::Character, :count).by(-1)
    end

    it "leaves another account's characters untouched" do
      other = create(:world_of_warcraft_character)
      profile['wow_accounts'] = []

      expect { described_class.new(account: account, profile: profile).synchronize }
        .not_to(change { other.reload.name })
    end
  end

  describe 'an empty payload' do
    let(:profile) { {} }

    it 'does not raise' do
      expect { synchronization.synchronize }.not_to raise_error
    end
  end
end
