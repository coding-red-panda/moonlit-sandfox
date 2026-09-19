require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  let(:token_url) { 'https://oauth.battle.net/token' }
  let(:userinfo_url) { 'https://oauth.battle.net/userinfo' }

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
  end

  # Drives POST /auth/battle_net and returns the state we were issued.
  def begin_flow
    post battle_net_auth_path
    Rack::Utils.parse_query(URI(response.location).query).fetch('state')
  end

  # Walks the whole happy path: consent, callback, session.
  def complete_flow(**claims)
    stub_battle_net(**claims)
    get callback_path, params: { code: 'auth-code', state: begin_flow }
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

    it 'keeps nothing but the account id in the session' do
      complete_flow

      expect(session.to_hash.keys - %w[flash session_id]).to contain_exactly('account_id')
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

  describe 'DELETE /logout' do
    it 'clears the session', :aggregate_failures do
      complete_flow

      delete logout_path

      expect(response).to redirect_to(root_path)
      expect(session[:account_id]).to be_nil
    end
  end
end
