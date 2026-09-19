class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_account, :signed_in?

  private

  # The session holds nothing but the account id; its absence means logged out.
  def current_account
    return @current_account if defined?(@current_account)

    @current_account = Account.find_by(id: session[:account_id])
  end

  def signed_in?
    current_account.present?
  end

  def require_authentication
    return if signed_in?

    redirect_to login_path, alert: t('authentication.required')
  end
end
