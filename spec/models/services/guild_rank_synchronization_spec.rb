require 'rails_helper'

RSpec.describe Services::GuildRankSynchronization, type: :model do
  subject(:synchronization) { described_class.new(account: account, client: client) }

  let(:account) { create(:account) }
  let(:wow_account) { create(:world_of_warcraft_account, account: account) }
  let(:client) { instance_spy(BattleNet::ApiClient, authenticate_application: access_token) }
  let(:access_token) { instance_spy(BattleNet::AccessToken, guild_roster: roster) }

  # Trimmed from a real roster response. Note what is not there: no rank name and
  # no class name. Blizzard hands out bare integers.
  let(:roster) do
    { 'members' => [{ 'character' => { 'id' => 180_318_917, 'name' => 'Keento' }, 'rank' => 1 }] }
  end

  before do
    Setting['guild.realm_slug'] = 'argent-dawn'
    Setting['guild.name_slug'] = 'moonlit-sandfox'
    create(:world_of_warcraft_guild_rank, rank: 1, name: 'Council', officer: true)
  end

  def character(battle_net_character_id: 180_318_917)
    create(:world_of_warcraft_character, world_of_warcraft_account: wow_account,
                                         battle_net_character_id: battle_net_character_id)
  end

  it 'stamps the roster rank onto a matching character' do
    keento = character

    expect { synchronization.synchronize }
      .to change { keento.reload.world_of_warcraft_guild_rank&.name }.to('Council')
  end

  # The roster needs no signed-in user, which is what lets this run in a job.
  it 'reads the roster with an application token rather than a user token' do
    synchronization.synchronize

    expect(client).to have_received(:authenticate_application)
  end

  it 'asks for the guild named in the settings' do
    synchronization.synchronize

    expect(access_token).to have_received(:guild_roster)
      .with(realm_slug: 'argent-dawn', name_slug: 'moonlit-sandfox')
  end

  it 'leaves a character who is not on the roster rankless' do
    stranger = character(battle_net_character_id: 999_999)

    synchronization.synchronize

    expect(stranger.reload.world_of_warcraft_guild_rank).to be_nil
  end

  it 'clears the rank of a character who has left the guild' do
    leaver = character(battle_net_character_id: 999_999)
    leaver.update!(world_of_warcraft_guild_rank: WorldOfWarcraft::GuildRank.sole)

    expect { synchronization.synchronize }
      .to change { leaver.reload.world_of_warcraft_guild_rank }.to(nil)
  end

  # The ladder is seeded by hand, so the game can introduce a rank we have no name
  # for. Better rankless than crashing the job.
  it 'leaves a character rankless when the roster rank is not seeded' do
    keento = character
    roster['members'].first['rank'] = 4

    synchronization.synchronize

    expect(keento.reload.world_of_warcraft_guild_rank).to be_nil
  end

  it 'ignores roster members who are not ours' do
    character
    roster['members'] << { 'character' => { 'id' => 116_305_220 }, 'rank' => 7 }

    expect { synchronization.synchronize }.not_to change(WorldOfWarcraft::Character, :count)
  end

  describe 'when no guild is configured' do
    before { Setting.delete_all }

    it 'skips the roster entirely', :aggregate_failures do
      expect(synchronization.synchronize).to be(false)
      expect(client).not_to have_received(:authenticate_application)
    end
  end

  describe 'when Battle.net cannot be reached' do
    before do
      allow(client).to receive(:authenticate_application)
        .and_raise(BattleNet::ApiClient::Error, 'Battle.net responded with 503')
    end

    # Ranks that cannot be refreshed are left as they were, not wiped.
    it 'reports failure without raising', :aggregate_failures do
      keento = character
      keento.update!(world_of_warcraft_guild_rank: WorldOfWarcraft::GuildRank.sole)

      expect(synchronization.synchronize).to be(false)
      expect(keento.reload.world_of_warcraft_guild_rank).to be_present
    end
  end
end
