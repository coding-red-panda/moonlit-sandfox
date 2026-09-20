module BattleNet
  # A live Battle.net access token, bound to the client that issued it.
  #
  # It exists for the length of one request and is then thrown away — see ADR-002.
  # The token is never exposed as an attribute and is kept out of #inspect so it
  # cannot leak into an exception report or a log line.
  class Session
    def initialize(client:, access_token:)
      @client = client
      @access_token = access_token
    end

    def userinfo
      @client.userinfo(access_token: @access_token)
    end

    def wow_profile
      @client.wow_profile(access_token: @access_token)
    end

    def guild_roster(realm_slug:, name_slug:)
      @client.guild_roster(realm_slug: realm_slug, name_slug: name_slug,
                           access_token: @access_token)
    end

    def inspect
      "#<#{self.class.name} (access token redacted)>"
    end
  end
end
