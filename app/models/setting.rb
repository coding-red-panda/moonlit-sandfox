# A tiny key/value store for operational values that must outlive a deploy but do
# not deserve a table of their own — the guild we match members against, say.
#
# Values are stored as strings; anything richer belongs in a real model.
class Setting < ApplicationRecord
  UNSET = Object.new.freeze
  private_constant :UNSET

  validates :key, presence: true, uniqueness: true

  class << self
    # Setting['guild.name_slug'] => "moonlit-sandfox" or nil when unset.
    def [](key)
      find_by(key: key.to_s)&.value
    end

    def []=(key, value)
      record = find_or_initialize_by(key: key.to_s)
      record.value = value
      record.save!
    end

    # Like Hash#fetch: raises KeyError when the setting is missing and no default
    # was given, so a misconfiguration fails loudly rather than silently doing nothing.
    def fetch(key, default = UNSET)
      value = self[key]
      return value if value.present?
      raise KeyError, "Setting #{key} is not configured" if default.equal?(UNSET)

      default
    end
  end
end
