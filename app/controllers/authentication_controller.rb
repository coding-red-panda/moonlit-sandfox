class AuthenticationController < ApplicationController
  rescue_from BattleNet::Client::Error, with: :battle_net_unavailable

  # GET /login — shows the "connect to Battle.net" button, or the current session.
  def login; end

  # POST /auth/battle_net — starts the authorization code flow.
  #
  # The session cookie is scoped to the host the browser is on. If that is not the
  # host in the registered redirect URI (browsing 127.0.0.1 while the portal has
  # localhost, say), the callback lands on a different host, arrives with no cookie
  # and fails the state check for reasons that look nothing like the real cause.
  # Send the user to the canonical host first instead.
  def create
    return redirect_to canonical_login_url, allow_other_host: true unless canonical_host?

    state = SecureRandom.urlsafe_base64(32)
    session[:battle_net_state] = state

    redirect_to BattleNet::Client.new.authorize_url(state: state), allow_other_host: true
  end

  # GET /callback — Battle.net sends the user back here with a code and our state.
  def callback
    rejection = rejection_reason(session.delete(:battle_net_state))
    return failure(rejection) if rejection

    claims = BattleNet::Client.new.userinfo(code: params[:code])

    sign_in(Account.from_userinfo(claims))
  end

  # DELETE /logout — clears our session only; the Battle.net SSO session remains.
  def destroy
    reset_session

    redirect_to root_path, notice: t('authentication.signed_out')
  end

  private

  def callback_uri
    @callback_uri ||= URI(BattleNet::Client.new.redirect_uri)
  end

  def canonical_host?
    request.host == callback_uri.host
  end

  def canonical_login_url
    login_url(protocol: callback_uri.scheme, host: callback_uri.host, port: callback_uri.port)
  end

  # Returns the locale key for why this callback is unusable, or nil if it is good.
  def rejection_reason(expected_state)
    return :cancelled if params[:error].present?
    return :invalid_state unless valid_state?(expected_state)
    return :missing_code if params[:code].blank?

    nil
  end

  def valid_state?(expected)
    expected.present? && params[:state].present? &&
      ActiveSupport::SecurityUtils.secure_compare(expected, params[:state])
  end

  def sign_in(account)
    reset_session
    session[:account_id] = account.id

    redirect_to root_path, notice: t('authentication.signed_in', battletag: account.battletag)
  end

  def failure(reason)
    redirect_to login_path, alert: t("authentication.#{reason}")
  end

  def battle_net_unavailable(error)
    Rails.logger.error("Battle.net authentication failed: #{error.message}")

    failure(:unavailable)
  end
end
