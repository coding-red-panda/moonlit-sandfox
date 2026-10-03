# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# The guild we match members against (docs/adr/002-authentication.md).
#
# Confirmed against the Battle.net API and the armory rather than guessed at:
# https://worldofwarcraft.blizzard.com/en-gb/worldsoul/eu/armory/guild/argent-dawn/moonlit-sandfox
# "Moonlit Sandfox" on Argent Dawn (EU), guild id 90944968, realm id 536.
#
# Seeded with find_or_create_by! rather than Setting#[]= on purpose: these are
# operational values meant to be changed at runtime, and re-running the seeds must
# not stamp on a realm transfer or a rename someone has already applied.
{
  'guild.realm_slug' => 'argent-dawn',
  'guild.name_slug' => 'moonlit-sandfox'
}.each do |key, value|
  Setting.find_or_create_by!(key: key) { |setting| setting.value = value }
end

# The guild's rank ladder (docs/adr/003-session-management.md).
#
# Blizzard's roster endpoint returns ranks as bare integers with no names, and has
# no concept of an officer, so both live here. Rank 0 is always the Guild Master.
#
# find_or_create_by! for the same reason as the settings above: renaming a rank or
# promoting one to officer is an operational change, and re-running the seeds must
# not undo it.
[
  [0, 'Caravan Leader', true],
  [1, 'Council', true],
  [2, 'Desert Fang', false],
  [3, 'Scroll Sage', false],
  [4, 'Scavenger', false],
  [5, 'Pathfinder', false],
  [6, 'New Tail', false],
  [7, 'Caravan Friend', false],
  [8, 'Friend/OOC Alt', false],
  [9, 'Neighbour', false]
].each do |rank, name, officer|
  WorldOfWarcraft::GuildRank.find_or_create_by!(rank: rank) do |guild_rank|
    guild_rank.name = name
    guild_rank.officer = officer
  end
end
