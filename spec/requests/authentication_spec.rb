require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  let(:token_url) { 'https://oauth.battle.net/token' }
  let(:userinfo_url) { 'https://oauth.battle.net/userinfo' }
  let(:profile_url) { 'https://eu.api.blizzard.com/profile/user/wow' }
  let(:roster_url) { 'https://eu.api.blizzard.com/data/wow/guild/silvermoon/moonlit-sandfox/roster' }

  before do
    # Must match the host in the configured redirect URI, or the flow refuses to start.
    host! 'localhost'

    allow(Rails.application.credentials).to receive(:battle_net)
      .and_return(client_id: 'test-client', client_secret: 'test-secret')
  end

  def stub_battle_net(sub: '987654321', battletag: 'Sandfox#2145')
    stub_request(:post, token_url).to_return(
      body: { access_token: 'live-token' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:get, userinfo_url).to_return(
      body: { sub: sub, battletag: battletag }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    stub_wow_api
  end

  # The World of Warcraft data is pulled in the same request, while the token lives.
  def stub_wow_api(status: 200)
    stub_request(:get, %r{\Ahttps://eu\.api\.blizzard\.com/}).to_return(
      status: status,
      body: { wow_accounts: [] }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  # Drives POST /auth/battle_net and returns the state we were issued.
  def begin_flow
    post battle_net_auth_path
    Rack::Utils.parse_query(URI(response.location).query).fetch('state')
  end

  # Walks the whole happy path: consent, callback, session.
  def complete_flow(**claims)
    stub_battle_net(**claims)
    state = begin_flow
    yield if block_given?
    get callback_path, params: { code: 'auth-code', state: state }
  end

  describe 'GET /login' do
    it 'offers the Battle.net button when signed out' do
      get login_path

      expect(response.body).to include('Connect with Battle.net')
    end

    it 'shows the battletag and a sign out button when signed in', :aggregate_failures do
      complete_flow

      get login_path

      expect(response.body).to include('Sandfox#2145')
      expect(response.body).to include('Sign out')
    end
  end

  describe 'POST /auth/battle_net' do
    it 'redirects to the Battle.net authorization endpoint' do
      post battle_net_auth_path

      expect(response).to redirect_to(%r{\Ahttps://oauth\.battle\.net/authorize\?})
    end

    it 'issues a state parameter' do
      expect(begin_flow).to be_present
    end

    it 'issues a different state on each attempt' do
      expect(begin_flow).not_to eq(begin_flow)
    end

    # The session cookie would be scoped to the wrong host and the callback would
    # arrive without it, failing the state check for a misleading reason.
    it 'sends the user to the redirect URI host before starting the flow' do
      post battle_net_auth_path, headers: { 'HOST' => '127.0.0.1' }

      expect(response).to redirect_to('http://localhost:3000/login')
    end

    it 'does not issue a state from the wrong host' do
      post battle_net_auth_path, headers: { 'HOST' => '127.0.0.1' }

      expect(session[:battle_net_state]).to be_nil
    end
  end

  describe 'GET /login showing the roster' do
    # Lazy, so it resolves after complete_flow has created the account.
    let(:wow_account) { create(:world_of_warcraft_account, account: Account.last) }

    def sign_in_and_reload
      complete_flow
      yield
      get login_path
    end

    def character_with(**attributes)
      create(:world_of_warcraft_character, world_of_warcraft_account: wow_account, **attributes)
    end

    def create_guilded_character
      create(:world_of_warcraft_character, :in_guild, world_of_warcraft_account: wow_account)
    end

    def guild_rank(rank, name, officer: false)
      create(:world_of_warcraft_guild_rank, rank: rank, name: name, officer: officer)
    end

    it 'says so while the background job has not reported back' do
      sign_in_and_reload { nil }

      expect(response.body).to include('your characters are fetched just after you sign in')
    end

    it 'lists a character with its realm, class and level', :aggregate_failures do
      sign_in_and_reload do
        character_with(name: 'Keento', realm_slug: 'argent-dawn',
                       character_class: 'Warrior', level: 90)
      end

      expect(response.body).to include('Keento', 'Argent Dawn', 'Warrior', '90')
    end

    it 'shows the rank held on a character' do
      sign_in_and_reload { character_with(world_of_warcraft_guild_rank: guild_rank(1, 'Council')) }

      expect(response.body).to include('Council')
    end

    it 'marks an officer rank as one' do
      sign_in_and_reload do
        character_with(world_of_warcraft_guild_rank: guild_rank(0, 'Caravan Leader', officer: true))
      end

      expect(response.body).to include('(officer)')
    end

    it 'says the player holds no rank when none of their characters are in the guild' do
      sign_in_and_reload { character_with }

      expect(response.body).to include('no character of yours is on the guild roster')
    end

    it "shows no other account's characters" do
      sign_in_and_reload { create(:world_of_warcraft_character, name: 'Stranger') }

      expect(response.body).not_to include('Stranger')
    end

    # The ranks are preloaded, so the page costs the same whether the player has one
    # character or twenty. Without that, each row would fetch its own rank.
    it 'does not query a rank per character' do
      complete_flow
      create_guilded_character
      baseline = count_queries { get login_path }
      2.times { create_guilded_character }

      expect(count_queries { get login_path }).to eq(baseline)
    end
  end

  describe 'GET /callback' do
    it 'creates an account and starts a session', :aggregate_failures do
      stub_battle_net
      state = begin_flow

      expect { get callback_path, params: { code: 'auth-code', state: state } }
        .to change(Account, :count).by(1)
      expect(session[:account_id]).to eq(Account.last.id)
    end

    it 'redirects to the root path' do
      complete_flow

      expect(response).to redirect_to(root_path)
    end

    it 'keeps nothing but the account id and the expiry in the session' do
      complete_flow

      expect(session.to_hash.keys - %w[flash session_id])
        .to contain_exactly('account_id', 'expires_at')
    end

    it 'starts a session that expires twelve hours from now' do
      freeze_time do
        complete_flow

        expect(session[:expires_at]).to eq(12.hours.from_now.to_i)
      end
    end

    it 'never puts the access token in the session' do
      complete_flow

      expect(session.to_hash.to_s).not_to include('live-token')
    end

    it 'signs in an existing account without duplicating it', :aggregate_failures do
      create(:account, battle_net_id: '987654321', battletag: 'OldName#1111')

      expect { complete_flow }.not_to change(Account, :count)
      expect(Account.last.battletag).to eq('Sandfox#2145')
    end

    it 'rejects a callback whose state does not match', :aggregate_failures do
      stub_battle_net
      begin_flow

      get callback_path, params: { code: 'auth-code', state: 'forged' }

      expect(response).to redirect_to(login_path)
      expect(session[:account_id]).to be_nil
    end

    it 'rejects a callback with no state at all', :aggregate_failures do
      stub_battle_net

      get callback_path, params: { code: 'auth-code' }

      expect(response).to redirect_to(login_path)
      expect(session[:account_id]).to be_nil
    end

    it 'does not exchange the code when the state is invalid' do
      stub_battle_net
      begin_flow

      get callback_path, params: { code: 'auth-code', state: 'forged' }

      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'consumes the state so a callback cannot be replayed' do
      stub_battle_net
      state = begin_flow
      get callback_path, params: { code: 'auth-code', state: state }

      get callback_path, params: { code: 'auth-code', state: state }

      expect(flash[:alert]).to include('could not be verified')
    end

    it 'handles the user cancelling consent' do
      get callback_path, params: { error: 'access_denied', state: begin_flow }

      expect(flash[:alert]).to include('cancelled')
    end

    it 'handles a missing authorization code' do
      get callback_path, params: { state: begin_flow }

      expect(flash[:alert]).to include('did not return an authorization code')
    end

    it 'handles Battle.net being unreachable', :aggregate_failures do
      stub_request(:post, token_url).to_timeout

      get callback_path, params: { code: 'auth-code', state: begin_flow }

      expect(flash[:alert]).to include('could not be reached')
      expect(session[:account_id]).to be_nil
    end
  end

  describe 'GET /callback pulling World of Warcraft data' do
    it 'hands the pull to a background job' do
      complete_flow

      expect(FetchCharactersJob).to have_been_enqueued.with(Account.last, anything)
    end

    # The whole point of the job is that the login does not wait on Battle.net.
    it 'reads no World of Warcraft data during the request itself' do
      complete_flow

      expect(a_request(:get, %r{\Ahttps://eu\.api\.blizzard\.com/})).not_to have_been_made
    end

    it 'seals the access token rather than passing it in the clear' do
      complete_flow

      expect(enqueued_jobs.last[:args].to_s).not_to include('live-token')
    end

    # Unsealing it again is what proves the envelope is the token, not a placeholder.
    it 'seals an envelope the job can open' do
      complete_flow
      envelope = enqueued_jobs.last[:args].last

      expect(BattleNet::AccessToken.unseal(envelope)).to be_a(BattleNet::AccessToken)
    end
  end

  # There is no protected route yet, so /login is the signal: it renders the
  # battletag for a live session and the connect button for a dead one.
  describe 'session expiry' do
    it 'keeps the session alive inside twelve hours' do
      complete_flow
      travel 11.hours

      get login_path

      expect(response.body).to include('Sandfox#2145')
    end

    it 'signs the user out once twelve hours have passed', :aggregate_failures do
      complete_flow
      travel 12.hours + 1.minute

      get login_path

      expect(response.body).to include('Connect with Battle.net')
      expect(session[:account_id]).to be_nil
    end

    it 'restarts the clock on a fresh login' do
      complete_flow
      travel_to 11.hours.from_now
      complete_flow

      expect(session[:expires_at]).to eq(12.hours.from_now.to_i)
    end
  end

  describe 'DELETE /logout' do
    it 'clears the session', :aggregate_failures do
      complete_flow

      delete logout_path

      expect(response).to redirect_to(root_path)
      expect(session[:account_id]).to be_nil
    end
  end
end
