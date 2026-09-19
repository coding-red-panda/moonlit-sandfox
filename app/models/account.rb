class Account < ApplicationRecord
  validates :battle_net_id, presence: true, uniqueness: true
  validates :battletag, presence: true

  # Creates or refreshes the local account for a set of Battle.net userinfo claims.
  # The `sub` claim is the stable account identifier; the battletag is display-only
  # and is re-read on every login because users can change it.
  def self.from_userinfo(claims)
    account = find_or_initialize_by(battle_net_id: claims.fetch('sub').to_s)
    account.battletag = claims.fetch('battletag')
    account.last_login_at = Time.current
    account.save!
    account
  end
end
