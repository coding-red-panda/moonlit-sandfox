require 'rails_helper'

RSpec.describe BattleNet::AccessToken, type: :model do
  subject(:token) { described_class.new(client: client, access_token: 'live-token') }

  let(:client) do
    instance_spy(BattleNet::ApiClient, userinfo: {}, wow_profile: {}, guild_roster: {})
  end

  it 'spends the token on the userinfo endpoint' do
    token.userinfo

    expect(client).to have_received(:userinfo).with(access_token: 'live-token')
  end

  it 'spends the token on the World of Warcraft profile' do
    token.wow_profile

    expect(client).to have_received(:wow_profile).with(access_token: 'live-token')
  end

  it 'spends the token on the guild roster' do
    token.guild_roster(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox')

    expect(client).to have_received(:guild_roster)
      .with(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox', access_token: 'live-token')
  end

  # An exception report or a `p token` must not hand the token to a log file.
  it 'keeps the access token out of inspect' do
    expect(token.inspect).not_to include('live-token')
  end

  # The envelope exists so a background job can carry the token through the
  # Solid Queue tables without the token itself ever landing in Postgres.
  describe 'sealing for a background job' do
    it 'does not leave the token readable in the envelope' do
      expect(token.sealed).not_to include('live-token')
    end

    it 'unseals back into a token that still spends' do
      described_class.unseal(token.sealed, client: client).userinfo

      expect(client).to have_received(:userinfo).with(access_token: 'live-token')
    end

    it 'refuses an envelope that has been tampered with' do
      expect(described_class.unseal("#{token.sealed}tampered", client: client)).to be_nil
    end

    it 'refuses an envelope sealed under a different key' do
      other = ActiveSupport::MessageEncryptor.new(SecureRandom.random_bytes(32))

      expect(described_class.unseal(other.encrypt_and_sign('live-token'), client: client)).to be_nil
    end

    # Battle.net kills the token at 24 hours; the envelope must not outlast it.
    it 'refuses an envelope older than the token it carries' do
      envelope = token.sealed
      travel described_class::LIFETIME + 1.minute

      expect(described_class.unseal(envelope, client: client)).to be_nil
    end

    it 'refuses a blank envelope' do
      expect(described_class.unseal(nil, client: client)).to be_nil
    end
  end
end
