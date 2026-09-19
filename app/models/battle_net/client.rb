require 'net/http'

module BattleNet
  # Minimal Battle.net OAuth2 / OIDC client covering the authorization code flow.
  #
  # Access tokens are deliberately never returned or stored: Battle.net issues no
  # usable refresh token, so a token is exchanged and spent within a single request.
  # See docs/adr/002-authentication.md.
  class Client
    class Error < StandardError
    end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def initialize(config: Rails.application.config_for(:battle_net),
                   credentials: Rails.application.credentials.battle_net)
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

    # Exchanges an authorization code for an access token and immediately spends it
    # on the userinfo endpoint. Returns the OIDC claims, notably `sub` and `battletag`.
    def userinfo(code:)
      fetch_userinfo(exchange_code(code))
    end

    private

    def exchange_code(code)
      body = post(
        @config.fetch(:token_url),
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirect_uri
      )

      body['access_token'].presence || raise(Error, 'Battle.net returned no access token')
    end

    def fetch_userinfo(access_token)
      uri = URI(@config.fetch(:userinfo_url))
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Accept'] = 'application/json'

      parse(perform(uri, request))
    end

    # Client credentials go in the Authorization header, not the body.
    def post(url, params)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(client_id, client_secret)
      request['Accept'] = 'application/json'
      request.set_form_data(params)

      parse(perform(uri, request))
    end

    def perform(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port,
                                 use_ssl: uri.scheme == 'https',
                                 open_timeout: OPEN_TIMEOUT,
                                 read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      raise Error, "Battle.net responded with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    rescue Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Error, "Battle.net request failed: #{e.class}: #{e.message}"
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Battle.net returned malformed JSON: #{e.message}"
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
