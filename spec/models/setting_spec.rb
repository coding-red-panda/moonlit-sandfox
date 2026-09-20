require 'rails_helper'

RSpec.describe Setting, type: :model do
  subject { build(:setting) }

  it { is_expected.to validate_presence_of(:key) }

  it 'rejects a duplicate key' do
    create(:setting, key: 'guild.name_slug')

    expect(build(:setting, key: 'guild.name_slug')).not_to be_valid
  end

  describe '.[]' do
    it 'returns the stored value' do
      create(:setting, key: 'guild.name_slug', value: 'moonlit-sandfox')

      expect(described_class['guild.name_slug']).to eq('moonlit-sandfox')
    end

    it 'returns nil for a key that was never set' do
      expect(described_class['guild.name_slug']).to be_nil
    end

    it 'accepts a symbol key' do
      create(:setting, key: 'guild.name_slug', value: 'moonlit-sandfox')

      expect(described_class[:'guild.name_slug']).to eq('moonlit-sandfox')
    end
  end

  describe '.[]=' do
    it 'creates the setting' do
      described_class['guild.realm_slug'] = 'silvermoon'

      expect(described_class['guild.realm_slug']).to eq('silvermoon')
    end

    it 'overwrites an existing setting without duplicating it', :aggregate_failures do
      create(:setting, key: 'guild.realm_slug', value: 'silvermoon')

      expect { described_class['guild.realm_slug'] = 'kazzak' }.not_to change(described_class, :count)
      expect(described_class['guild.realm_slug']).to eq('kazzak')
    end
  end

  describe '.fetch' do
    it 'returns the stored value' do
      create(:setting, key: 'guild.realm_slug', value: 'silvermoon')

      expect(described_class.fetch('guild.realm_slug')).to eq('silvermoon')
    end

    it 'raises when the setting is missing and no default was given' do
      expect { described_class.fetch('guild.realm_slug') }
        .to raise_error(KeyError, /guild.realm_slug/)
    end

    it 'returns the default when the setting is missing' do
      expect(described_class.fetch('guild.realm_slug', 'silvermoon')).to eq('silvermoon')
    end

    it 'treats a blank value as missing' do
      create(:setting, key: 'guild.realm_slug', value: '')

      expect(described_class.fetch('guild.realm_slug', 'silvermoon')).to eq('silvermoon')
    end
  end
end
