require 'webmock/rspec'

# Specs must never reach the live Battle.net endpoints, even though development does.
WebMock.disable_net_connect!(allow_localhost: true)
