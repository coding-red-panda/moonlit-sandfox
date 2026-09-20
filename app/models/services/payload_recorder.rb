module Services
  # Writes raw Battle.net API responses to log/payloads so their shape can be studied
  # before anything is modelled on it. See ADR-002, "Recording payloads instead of
  # modelling them".
  #
  # The payloads contain real account and character data, so the directory is ignored
  # by git. This is a reconnaissance tool, not a cache — nothing ever reads it back.
  class PayloadRecorder
    # Overridden in the test suite so specs do not litter the real log directory.
    class_attribute :directory, default: Rails.root.join('log/payloads')

    class << self
      # Returns the path written, or nil if it could not be written. Recording is a
      # diagnostic, so a failure here must never break the request that triggered it.
      def record(name, payload)
        directory.mkpath
        path = directory.join(filename(name))
        path.write(JSON.pretty_generate(payload))
        Rails.logger.info("Recorded Battle.net payload at #{path}")

        path
      rescue SystemCallError, JSON::GeneratorError => e
        Rails.logger.warn("Could not record Battle.net payload #{name}: #{e.class}: #{e.message}")

        nil
      end

      private

      def filename(name)
        "#{Time.current.utc.strftime('%Y%m%d%H%M%S%L')}-#{name.to_s.parameterize}.json"
      end
    end
  end
end
