require 'rails_helper'

RSpec.describe SynchronizeGuildRanksJob, type: :job do
  let(:account) { create(:account) }
  let(:synchronization) { instance_spy(Services::GuildRankSynchronization) }

  before do
    allow(Services::GuildRankSynchronization).to receive(:new).and_return(synchronization)
  end

  it 'synchronizes the ranks for the account it was given', :aggregate_failures do
    described_class.perform_now(account)

    expect(Services::GuildRankSynchronization).to have_received(:new).with(account: account)
    expect(synchronization).to have_received(:synchronize)
  end

  # Nothing here needs the user's token, so the job can be re-run at any time.
  it 'can be enqueued on its own' do
    expect { described_class.perform_later(account) }.to have_enqueued_job(described_class)
  end
end
