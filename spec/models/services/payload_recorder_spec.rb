require 'rails_helper'

RSpec.describe Services::PayloadRecorder, type: :model do
  let(:payload) { { 'wow_accounts' => [{ 'id' => 1 }] } }

  describe '.record' do
    it 'writes the payload as JSON' do
      path = described_class.record('wow-profile', payload)

      expect(JSON.parse(path.read)).to eq(payload)
    end

    it 'names the file after the payload and the time it arrived', :aggregate_failures do
      path = travel_to(Time.utc(2026, 9, 20, 11, 30, 15)) { described_class.record('wow-profile', payload) }

      expect(path.basename.to_s).to start_with('20260920113015')
      expect(path.basename.to_s).to end_with('-wow-profile.json')
    end

    it 'creates the directory when it does not exist yet' do
      FileUtils.rm_rf(described_class.directory)

      expect(described_class.record('wow-profile', payload)).to exist
    end

    it 'returns nil rather than raising when the write fails' do
      allow(described_class.directory).to receive(:mkpath).and_raise(Errno::EACCES)

      expect(described_class.record('wow-profile', payload)).to be_nil
    end
  end
end
