# World of Warcraft game data (docs/adr/003-session-management.md).
#
# The tables are prefixed because a Battle.net account and a World of Warcraft
# account are different things: without this, WorldOfWarcraft::Account would map
# onto the top-level `accounts` table and quietly share it with Account.
module WorldOfWarcraft
  def self.table_name_prefix
    'world_of_warcraft_'
  end
end
