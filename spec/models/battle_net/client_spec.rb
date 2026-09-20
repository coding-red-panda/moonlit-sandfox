require 'rails_helper'

RSpec.describe BattleNet::Client, type: :model do
  subject(:client) { described_class.new(credentials: credentials) }

  let(:credentials) { { client_id: 'test-client', client_secret: 'test-secret' } }
  let(:token_url) { 'https://oauth.battle.net/token' }
  let(:userinfo_url) { 'https://oauth.battle.net/userinfo' }
  let(:basic_auth) { Base64.strict_encode64('test-client:test-secret') }

  describe '#authorize_url' do
    subject(:url) { URI(client.authorize_url(state: 'abc123')) }

    let(:query) { Rack::Utils.parse_query(url.query) }

    it 'points at the Battle.net authorization endpoint' do
      expect(url.origin + url.path).to eq('https://oauth.battle.net/authorize')
    end

    it 'requests the openid and wow.profile scopes as one space-separated value' do
      expect(query['scope']).to eq('openid wow.profile')
    end

    it 'carries the client id, redirect uri, response type and state' do
      expect(query).to include('client_id' => 'test-client', 'response_type' => 'code',
                               'redirect_uri' => 'http://localhost:3000/callback', 'state' => 'abc123')
    end

    it 'never leaks the client secret' do
      expect(url.to_s).not_to include('test-secret')
    end
  end

  describe '#authenticate' do
    before do
      stub_request(:post, token_url).to_return(
        body: { access_token: 'live-token', token_type: 'bearer' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, userinfo_url).to_return(
        body: { sub: '987654321', battletag: 'Sandfox#2145' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    it 'returns the userinfo claims' do
      expect(client.authenticate(code: 'auth-code').userinfo).to include(
        'sub' => '987654321',
        'battletag' => 'Sandfox#2145'
      )
    end

    it 'authenticates the token request with HTTP Basic rather than body params' do
      client.authenticate(code: 'auth-code').userinfo

      expect(a_request(:post, token_url)
        .with(headers: { 'Authorization' => "Basic #{basic_auth}" })).to have_been_made
    end

    it 'keeps the client secret out of the request body' do
      client.authenticate(code: 'auth-code').userinfo

      expect(a_request(:post, token_url).with { |req| req.body.include?('client_secret') })
        .not_to have_been_made
    end

    it 'sends the authorization code and redirect uri to the token endpoint' do
      client.authenticate(code: 'auth-code').userinfo

      expect(a_request(:post, token_url)
        .with(body: hash_including('grant_type' => 'authorization_code', 'code' => 'auth-code',
                                   'redirect_uri' => 'http://localhost:3000/callback'))).to have_been_made
    end

    it 'spends the access token on the userinfo endpoint as a bearer token' do
      client.authenticate(code: 'auth-code').userinfo

      expect(a_request(:get, userinfo_url)
        .with(headers: { 'Authorization' => 'Bearer live-token' })).to have_been_made
    end
  end

  describe 'World of Warcraft data endpoints' do
    # Plain methods rather than lets: the outer group already memoizes its quota.
    def profile_url
      'https://eu.api.blizzard.com/profile/user/wow'
    end

    def roster_url
      'https://eu.api.blizzard.com/data/wow/guild/silvermoon/moonlit-sandfox/roster'
    end

    def query
      { namespace: 'profile-eu', locale: 'en_GB' }
    end

    before do
      stub_request(:get, /eu\.api\.blizzard\.com/).to_return(
        body: { members: [] }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end

    it 'reads the profile from the EU host with the namespace and locale' do
      client.wow_profile(access_token: 'live-token')

      expect(a_request(:get, profile_url).with(query: query)).to have_been_made
    end

    it 'sends the access token as a bearer token' do
      client.wow_profile(access_token: 'live-token')

      expect(a_request(:get, profile_url)
        .with(query: query, headers: { 'Authorization' => 'Bearer live-token' })).to have_been_made
    end

    it 'builds the roster path from the realm and guild slugs' do
      client.guild_roster(realm_slug: 'silvermoon', name_slug: 'moonlit-sandfox',
                          access_token: 'live-token')

      expect(a_request(:get, roster_url).with(query: query)).to have_been_made
    end

    it 'returns the parsed body' do
      expect(client.wow_profile(access_token: 'live-token')).to eq('members' => [])
    end
  end

  describe 'failure handling' do
    it 'raises when the token endpoint rejects the code' do
      stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_grant"}')

      expect { client.authenticate(code: 'bad').userinfo }.to raise_error(described_class::Error, /400/)
    end

    it 'raises when the token endpoint returns no access token' do
      stub_request(:post, token_url).to_return(
        body: '{}', headers: { 'Content-Type' => 'application/json' }
      )

      expect { client.authenticate(code: 'auth-code').userinfo }
        .to raise_error(described_class::Error, /no access token/)
    end

    it 'raises when the response is not JSON' do
      stub_request(:post, token_url).to_return(body: '<html>gateway error</html>')

      expect { client.authenticate(code: 'auth-code').userinfo }
        .to raise_error(described_class::Error, /malformed JSON/)
    end

    it 'raises when the connection times out' do
      stub_request(:post, token_url).to_timeout

      expect { client.authenticate(code: 'auth-code').userinfo }
        .to raise_error(described_class::Error, /request failed/)
    end

    it 'raises when the credentials are missing' do
      bare = described_class.new(credentials: nil)

      expect { bare.authorize_url(state: 'abc') }
        .to raise_error(described_class::Error, /Missing battle_net.client_id/)
    end
  end
end
