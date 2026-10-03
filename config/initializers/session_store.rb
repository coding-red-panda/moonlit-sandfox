# A browser session lasts 12 hours (docs/adr/003-session-management.md).
#
# Battle.net issues no usable refresh token and re-prompts for consent on every
# authorization, so a short session is what keeps the granted permissions fresh:
# the user re-affirms them well inside the 24 hours their access token would live.
#
# expire_after only asks the browser to drop the cookie. A client is free to keep
# sending an expired one, so the deadline is also written into the session payload
# and re-checked server-side in ApplicationController#current_account.
Rails.application.config.x.session_duration = 12.hours

Rails.application.config.session_store :cookie_store,
                                       key: '_moonlit_sandfox_session',
                                       expire_after: Rails.application.config.x.session_duration
