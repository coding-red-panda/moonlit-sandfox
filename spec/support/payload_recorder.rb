require 'fileutils'

# Recording a payload is a real file write. Point it at tmp/ so the suite never
# litters log/payloads with fixture data.
RSpec.configure do |config|
  config.before(:suite) do
    Services::PayloadRecorder.directory = Rails.root.join('tmp/spec-payloads')
  end

  config.after(:suite) do
    FileUtils.rm_rf(Services::PayloadRecorder.directory)
  end
end
