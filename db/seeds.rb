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
