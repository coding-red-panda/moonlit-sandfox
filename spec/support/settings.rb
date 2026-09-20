# CI runs `bin/rails db:prepare`, which loads db/seeds.rb into a freshly created
# database — so the test database arrives with the guild settings already written.
#
# Settings are global mutable state that specs make assertions about, including
# assertions about a key being absent. Every example therefore starts from an empty
# table and sets up whatever it needs itself, rather than inheriting whatever the
# seeds happened to write. Transactional fixtures roll the deletion back.
RSpec.configure do |config|
  config.before { Setting.delete_all }
end
