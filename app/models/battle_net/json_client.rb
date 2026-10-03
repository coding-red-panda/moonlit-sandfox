require 'net/http'

module BattleNet
  # The JSON-over-HTTP plumbing every Battle.net call shares: bearer GETs, form
  # POSTs authenticated with the client credentials, timeouts, and turning any
  # kind of failure into a single Error the callers can rescue.
  #
  # ApiClient inherits from this so the endpoint knowledge stays separate from the
  # transport. Error is defined here and reached through the subclass, so
  # BattleNet::ApiClient::Error remains the name callers rescue.
  class JsonClient
    class Error < StandardError
    end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    private

    def get(url, access_token:)
      uri = URI(url)
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
  end
end
