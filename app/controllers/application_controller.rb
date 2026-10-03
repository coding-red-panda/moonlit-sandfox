class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_account, :signed_in?

  private

  # The session holds the account id and the deadline it expires on; the absence
  # of either means logged out. The cookie carries an expire_after as well, but a
  # client is free to keep sending an expired cookie, so the deadline is re-checked
  # here on every request (ADR-003).
  def current_account
    return @current_account if defined?(@current_account)

    reset_session if session_expired?

    @current_account = Account.find_by(id: session[:account_id])
  end

  # Starts a 12-hour session. reset_session first so a fixated session id cannot
  # survive the privilege change.
  def start_session(account)
    reset_session
    session[:account_id] = account.id
    session[:expires_at] = Rails.application.config.x.session_duration.from_now.to_i
  end

  # A session with an account but no deadline predates ADR-003, or was tampered
  # with; either way it is not one we are willing to honour.
  def session_expired?
    return false if session[:account_id].blank?

    session[:expires_at].blank? || Time.zone.at(session[:expires_at].to_i).past?
  end

  def signed_in?
    current_account.present?
  end

  def require_authentication
    return if signed_in?

    redirect_to login_path, alert: t('authentication.required')
  end
end
