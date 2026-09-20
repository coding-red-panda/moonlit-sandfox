require 'rails_helper'

RSpec.describe Services::GuildSynchronization, type: :model do
  subject(:synchronization) { described_class.new(account: account, session: session, recorder: recorder) }

  let(:account) { create(:account) }
  let(:profile) { { 'wow_accounts' => [{ 'characters' => [] }] } }
  let(:roster) { { 'members' => [{ 'rank' => 0 }] } }
  let(:recorder) { class_spy(Services::PayloadRecorder) }

  let(:session) do
    instance_double(BattleNet::Session, wow_profile: profile, guild_roster: roster)
  end

  def configure_guild
    Setting['guild.realm_slug'] = 'silvermoon'
    Setting['guild.name_slug'] = 'moonlit-sandfox'
  end

  describe '#call' do
    before { configure_guild }

    it 'records the World of Warcraft profile' do
      synchronization.call

      expect(recorder).to have_received(:record).with('wow-profile', profile)
    end

    it 'records the roster of the configured guild' do
      synchronization.call

      expect(recorder).to have_received(:record).with('guild-roster', roster)
    end

    it 'asks for the guild named in the settings' do
      synchronization.call

      expect(session).to have_received(:guild_roster)
        .with(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox')
    end

    it 'reports success' do
      expect(synchronization.call).to be(true)
    end

    # Nothing is written yet: we are still learning the shape of the responses.
    it 'does not change the account' do
      expect { synchronization.call }.not_to(change { account.reload.attributes })
    end
  end

  describe '#call without the guild settings' do
    it 'still records the profile' do
      synchronization.call

      expect(recorder).to have_received(:record).with('wow-profile', profile)
    end

    it 'does not call the roster endpoint' do
      synchronization.call

      expect(session).not_to have_received(:guild_roster)
    end

    it 'does not record a roster' do
      synchronization.call

      expect(recorder).not_to have_received(:record).with('guild-roster', anything)
    end

    it 'skips the roster when only the realm is configured' do
      Setting['guild.realm_slug'] = 'silvermoon'

      synchronization.call

      expect(session).not_to have_received(:guild_roster)
    end
  end

  # The account is signed in either way; losing the guild data costs nothing that
  # the next login does not recover.
  describe '#call when Battle.net fails' do
    before do
      configure_guild
      allow(session).to receive(:wow_profile).and_raise(BattleNet::Client::Error, 'boom')
    end

    it 'does not raise' do
      expect { synchronization.call }.not_to raise_error
    end

    it 'reports failure' do
      expect(synchronization.call).to be(false)
    end

    it 'records nothing' do
      synchronization.call

      expect(recorder).not_to have_received(:record)
    end
  end
end
