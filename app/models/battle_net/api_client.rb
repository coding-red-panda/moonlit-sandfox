module BattleNet
  # Minimal Battle.net OAuth2 / OIDC client covering the authorization code flow
  # and the handful of World of Warcraft profile endpoints we read during a login.
  #
  # Access tokens are never written to a table in the clear: Battle.net issues no
  # usable refresh token, so one is exchanged, spent and then gone. Every call that
  # needs a token takes it as an argument rather than holding it. ADR-003 lets a
  # token outlive its request to reach a background job, but only sealed in an
  # encrypted envelope — see BattleNet::AccessToken#sealed.
  # See docs/adr/002-authentication.md and docs/adr/003-session-management.md.
  class ApiClient < JsonClient
    def initialize(config: Rails.application.config_for(:battle_net),
                   credentials: Rails.application.credentials.battle_net)
      super()
      @config = config
      @credentials = credentials
    end

    # The callback URL registered on the developer portal. Cookies are scoped by host,
    # so the browser must already be on this host when the flow starts.
    def redirect_uri
      @config.fetch(:redirect_uri)
    end

    # The URL the user is sent to in order to grant consent.
    def authorize_url(state:)
      uri = URI(@config.fetch(:authorize_url))
      uri.query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: 'code',
        scope: @config.fetch(:scope),
        state: state
      )
      uri.to_s
    end

    # Exchanges an authorization code for an AccessToken holding the live token.
    def authenticate(code:)
      AccessToken.new(client: self, access_token: exchange_code(code))
    end

    # Authenticates as the application itself, with no user involved. Guild and
    # roster endpoints are game data rather than account data, so a client
    # credentials token reaches them — which is what lets the roster be read from
    # a background job long after the user's own token has been spent (ADR-003).
    def authenticate_application
      AccessToken.new(client: self, access_token: request_application_token)
    end

    # The OIDC claims, notably `sub` and `battletag`.
    def userinfo(access_token:)
      get(@config.fetch(:userinfo_url), access_token: access_token)
    end

    # The signed-in user's World of Warcraft account: their characters, each with
    # the realm and guild it belongs to. Requires the `wow.profile` scope.
    def wow_profile(access_token:)
      api_get('/profile/user/wow', access_token: access_token)
    end

    # The full roster of a guild, including each member's rank. Ranks are integers
    # where 0 is the Guild Master.
    def guild_roster(realm_slug:, name_slug:, access_token:)
      api_get("/data/wow/guild/#{escape(realm_slug)}/#{escape(name_slug)}/roster",
              access_token: access_token)
    end

    private

    def request_application_token
      body = post(@config.fetch(:token_url), grant_type: 'client_credentials')

      body['access_token'].presence || raise(Error, 'Battle.net returned no application token')
    end

    def exchange_code(code)
      body = post(
        @config.fetch(:token_url),
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirect_uri
      )

      body['access_token'].presence || raise(Error, 'Battle.net returned no access token')
    end

    # Data APIs are region-specific and need the namespace and locale on every call.
    def api_get(path, access_token:)
      uri = URI.join(@config.fetch(:api_url), path)
      uri.query = URI.encode_www_form(
        namespace: @config.fetch(:namespace),
        locale: @config.fetch(:locale)
      )

      get(uri.to_s, access_token: access_token)
    end

    def escape(segment)
      ERB::Util.url_encode(segment.to_s)
    end

    def client_id
      credential(:client_id)
    end

    def client_secret
      credential(:client_secret)
    end

    def credential(key)
      value = @credentials.try(:[], key)
      value.presence || raise(Error, "Missing battle_net.#{key} in Rails credentials")
    end
  end
end
