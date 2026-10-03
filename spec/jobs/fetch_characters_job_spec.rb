require 'rails_helper'

RSpec.describe FetchCharactersJob, type: :job do
  let(:account) { create(:account) }
  let(:client) { instance_spy(BattleNet::ApiClient, wow_profile: profile) }
  let(:access_token) { BattleNet::AccessToken.new(client: client, access_token: 'live-token') }
  let(:profile) do
    {
      'wow_accounts' => [
        {
          'id' => 3_547_048,
          'characters' => [
            { 'id' => 180_318_917, 'name' => 'Keento', 'level' => 90,
              'realm' => { 'slug' => 'argent-dawn' },
              'playable_class' => { 'name' => 'Warrior' } }
          ]
        }
      ]
    }
  end

  # The job unseals with its own client, so the stub has to be on the class.
  before { allow(BattleNet::ApiClient).to receive(:new).and_return(client) }

  it 'stores the characters the profile reports' do
    expect { described_class.perform_now(account, access_token.sealed) }
      .to change(WorldOfWarcraft::Character, :count).by(1)
  end

  it 'spends the sealed token on the profile endpoint' do
    described_class.perform_now(account, access_token.sealed)

    expect(client).to have_received(:wow_profile).with(access_token: 'live-token')
  end

  # Ranks need the roster, which needs no user token, so they are a job of their own.
  it 'hands the ranks on to the roster job' do
    described_class.perform_now(account, access_token.sealed)

    expect(SynchronizeGuildRanksJob).to have_been_enqueued.with(account)
  end

  describe 'when the envelope has expired' do
    it 'gives up rather than calling Battle.net', :aggregate_failures do
      envelope = access_token.sealed
      travel BattleNet::AccessToken::LIFETIME + 1.minute

      described_class.perform_now(account, envelope)

      expect(client).not_to have_received(:wow_profile)
      expect(SynchronizeGuildRanksJob).not_to have_been_enqueued
    end
  end

  describe 'when Battle.net is unreachable' do
    before do
      allow(client).to receive(:wow_profile)
        .and_raise(BattleNet::ApiClient::Error, 'Battle.net responded with 503')
    end

    it 'retries rather than failing outright' do
      expect { described_class.perform_now(account, access_token.sealed) }
        .to have_enqueued_job(described_class)
    end
  end

  # The argument is serialised into the Solid Queue tables, and the log would be
  # the other place the ciphertext could end up.
  it 'keeps its arguments out of the log' do
    expect(described_class.log_arguments).to be(false)
  end
end
