# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/lan_channel'

describe PuppetX::Ipmi::LanChannel do
  describe '.default_channel' do
    it 'uses an integer title as the channel' do
      expect(described_class.default_channel('3')).to eq(3)
    end

    it 'accepts a numeric title' do
      expect(described_class.default_channel(2)).to eq(2)
    end

    it 'falls back to 1 for a non-integer title' do
      expect(described_class.default_channel('lan1')).to eq(1)
    end

    it 'falls back to 1 for a nil title' do
      expect(described_class.default_channel(nil)).to eq(1)
    end

    it 'does not consult Facter' do
      Facter.expects(:value).never

      described_class.default_channel('lan1')
    end
  end

  describe 'when included in a type' do
    let(:type) do
      mixin = described_class
      Puppet::Type.newtype(:lan_channel_probe) do
        include mixin

        newparam(:name, namevar: true)
      end
    end

    after { Puppet::Type.rmtype(:lan_channel_probe) }

    it 'adds a lan_channel parameter' do
      expect(type.attrtype(:lan_channel)).to eq(:param)
    end

    it 'derives lan_channel from an integer title' do
      expect(type.new(name: '4')[:lan_channel]).to eq(4)
    end

    it 'defaults lan_channel to 1 for a free-form title' do
      expect(type.new(name: 'probe')[:lan_channel]).to eq(1)
    end

    it 'munges an explicit lan_channel to an Integer' do
      expect(type.new(name: 'probe', lan_channel: '7')[:lan_channel]).to eq(7)
    end

    [0, 16, 'abc', -1].each do |bad|
      it "rejects lan_channel #{bad.inspect}" do
        expect { type.new(name: 'probe', lan_channel: bad) }
          .to raise_error(Puppet::Error, %r{lan_channel must be an integer between 1 and 15})
      end
    end

    [1, 15].each do |good|
      it "accepts the boundary lan_channel #{good}" do
        expect(type.new(name: 'probe', lan_channel: good)[:lan_channel]).to eq(good)
      end
    end

    describe '#pre_run_check' do
      def catalog_with(*params)
        catalog = Puppet::Resource::Catalog.new
        resources = params.map { |p| type.new(p) }
        resources.each { |r| catalog.add_resource(r) }
        resources
      end

      it 'is a no-op without a catalog' do
        expect { type.new(name: 'probe').pre_run_check }.not_to raise_error
      end

      it 'rejects two resources on one channel, naming both' do
        first, = catalog_with({ name: 'b' }, { name: 'a', lan_channel: 1 })

        expect { first.pre_run_check }
          .to raise_error(Puppet::Error, %r{Multiple lan_channel_probe resources target channel 1: a, b})
      end

      it 'allows resources on different channels' do
        first, = catalog_with({ name: 'a' }, { name: 'b', lan_channel: 2 })

        expect { first.pre_run_check }.not_to raise_error
      end
    end
  end
end
