# CI runs `bin/rails db:prepare`, which loads db/seeds.rb into a freshly created
# database — so the test database arrives with the whole rank ladder written.
#
# Specs build the ranks they need, and assert on ranks being absent, so every
# example starts from an empty table rather than inheriting the seeds. Without
# this the suite passes locally and fails in CI on duplicate ranks.
# Transactional fixtures roll the deletion back.
RSpec.configure do |config|
  config.before { WorldOfWarcraft::GuildRank.delete_all }
end
