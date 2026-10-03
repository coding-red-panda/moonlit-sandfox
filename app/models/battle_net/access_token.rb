module BattleNet
  # A live Battle.net access token, bound to the client that issued it.
  #
  # The token is never exposed as an attribute and is kept out of #inspect so it
  # cannot leak into an exception report or a log line.
  #
  # ADR-003 moves the World of Warcraft pull into a background job, which outlives
  # the request the token was issued in. Solid Queue serialises job arguments into
  # Postgres, so the token crosses that boundary sealed in an encrypted envelope
  # (#sealed) and is opened again on the other side (.unseal). A leaked jobs table
  # then yields ciphertext that is worthless without secret_key_base, and the
  # envelope times itself out even if the row outlives the job.
  class AccessToken
    # Battle.net access tokens are good for 24 hours. The envelope must not outlive
    # the credential inside it, or a job would wake up holding a token already dead.
    LIFETIME = 24.hours

    # Salts the envelope key off secret_key_base. Distinct from every other derived
    # key in the app, so an envelope cannot be replayed into a different purpose.
    KEY_PURPOSE = 'battle_net access token'.freeze

    class << self
      # Rebuilds a token from the envelope #sealed produced. Returns nil when the
      # envelope has expired, was tampered with, or was sealed under another key —
      # all of which mean the same thing to a caller: there is no token to spend.
      def unseal(envelope, client: ApiClient.new)
        access_token = envelope.present? && encryptor.decrypt_and_verify(envelope)

        new(client: client, access_token: access_token) if access_token.present?
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      # CachingKeyGenerator memoises the derivation, so this is cheap to call often.
      def encryptor
        key = Rails.application.key_generator.generate_key(
          KEY_PURPOSE, ActiveSupport::MessageEncryptor.key_len
        )

        ActiveSupport::MessageEncryptor.new(key)
      end
    end

    def initialize(client:, access_token:)
      @client = client
      @access_token = access_token
    end

    # An encrypted, self-expiring envelope that is safe to hand to a background job.
    def sealed
      self.class.encryptor.encrypt_and_sign(@access_token, expires_in: LIFETIME)
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
