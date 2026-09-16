# Lets specs call `create(:user)` instead of `FactoryBot.create(:user)`.
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
