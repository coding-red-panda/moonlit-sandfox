require 'rails_helper'

RSpec.describe BattleNet::Session, type: :model do
  subject(:session) { described_class.new(client: client, access_token: 'live-token') }

  let(:client) do
    instance_spy(BattleNet::Client, userinfo: {}, wow_profile: {}, guild_roster: {})
  end

  it 'spends the token on the userinfo endpoint' do
    session.userinfo

    expect(client).to have_received(:userinfo).with(access_token: 'live-token')
  end

  it 'spends the token on the World of Warcraft profile' do
    session.wow_profile

    expect(client).to have_received(:wow_profile).with(access_token: 'live-token')
  end

  it 'spends the token on the guild roster' do
    session.guild_roster(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox')

    expect(client).to have_received(:guild_roster)
      .with(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox', access_token: 'live-token')
  end

  # An exception report or a `p session` must not hand the token to a log file.
  it 'keeps the access token out of inspect' do
    expect(session.inspect).not_to include('live-token')
  end
end
