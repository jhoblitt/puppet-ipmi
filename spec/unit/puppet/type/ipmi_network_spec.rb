# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_network'

describe Puppet::Type.type(:ipmi_network) do
  describe 'when validating attributes' do
    %i[name lan_channel].each do |param|
      it "has a #{param} parameter" do
        expect(described_class.attrtype(param)).to eq(:param)
      end
    end

    %i[type ip netmask gateway].each do |prop|
      it "has a #{prop} property" do
        expect(described_class.attrtype(prop)).to eq(:property)
      end
    end
  end

  describe 'when validating values' do
    it 'defaults lan_channel to 1 for non-integer title' do
      Facter.stubs(:value).with(:kernel).returns('Linux')
      Facter.stubs(:value).with('ipmi.default.channel').returns(nil)
      resource = described_class.new(name: 'mynetwork')
      expect(resource[:lan_channel]).to eq(1)
    end

    it 'derives lan_channel from integer title' do
      resource = described_class.new(name: '3')
      expect(resource[:lan_channel]).to eq(3)
    end

    it 'does not read compiler-local facts for the channel default' do
      Facter.expects(:value).with('ipmi.default.channel').never
      resource = described_class.new(name: 'mynetwork')
      expect(resource[:lan_channel]).to eq(1)
    end

    it 'accepts an explicitly supplied lan_channel' do
      resource = described_class.new(name: 'mynetwork', lan_channel: 2)
      expect(resource[:lan_channel]).to eq(2)
    end

    it 'has no default type' do
      resource = described_class.new(name: 'test')
      expect(resource[:type]).to be_nil
    end

    it 'accepts dhcp as type' do
      resource = described_class.new(name: 'test', type: 'dhcp')
      expect(resource[:type]).to eq(:dhcp)
    end

    it 'accepts static as type' do
      resource = described_class.new(name: 'test', type: 'static', ip: '192.168.1.1', netmask: '255.255.255.0', gateway: '192.168.1.0')
      expect(resource[:type]).to eq(:static)
    end

    it 'rejects invalid IP addresses' do
      expect do
        described_class.new(name: 'test', ip: 'not-an-ip')
      end.to raise_error(Puppet::Error, %r{Invalid IP address})
    end

    it 'rejects invalid netmask' do
      expect do
        described_class.new(name: 'test', netmask: 'bad')
      end.to raise_error(Puppet::Error, %r{Invalid netmask})
    end

    it 'rejects invalid gateway' do
      expect do
        described_class.new(name: 'test', gateway: 'bad')
      end.to raise_error(Puppet::Error, %r{Invalid gateway})
    end

    it 'accepts valid IP addresses' do
      resource = described_class.new(name: 'test', type: 'static', ip: '192.168.1.1', netmask: '255.255.255.0', gateway: '192.168.1.0')
      expect(resource[:ip]).to eq('192.168.1.1')
    end

    it 'rejects a static configuration missing ip or netmask' do
      expect do
        described_class.new(name: 'test', type: 'static', ip: '192.168.1.1')
      end.to raise_error(Puppet::Error, %r{must both be set when type is 'static' \(missing: netmask\)})
    end

    it 'rejects a bare static configuration' do
      expect do
        described_class.new(name: 'test', type: 'static')
      end.to raise_error(Puppet::Error, %r{must both be set when type is 'static'})
    end

    it 'accepts a static configuration without a gateway' do
      resource = described_class.new(name: 'test', type: 'static', ip: '192.168.1.1', netmask: '255.255.255.0')
      expect(resource[:gateway]).to be_nil
    end

    it 'complains when you mix parameters' do
      expect do
        described_class.new(name: 'test', type: 'dhcp', ip: '192.168.1.1')
      end.to raise_error(Puppet::Error, %r{cannot be set})
    end
  end

  describe 'pre-run duplicate channel check' do
    let(:static_params) { { type: 'static', ip: '192.168.1.1', netmask: '255.255.255.0', gateway: '192.168.1.0' } }

    it 'raises when two resources target the same channel' do
      resource_a = described_class.new(name: 'net_a', lan_channel: 1, type: 'dhcp')
      resource_b = described_class.new({ name: 'net_b', lan_channel: 1 }.merge(static_params))
      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource_a)
      catalog.add_resource(resource_b)

      expect { resource_a.pre_run_check }.to raise_error(Puppet::Error, %r{Multiple ipmi_network resources target channel 1})
    end

    it 'allows resources targeting different channels' do
      resource_a = described_class.new(name: 'net_a', lan_channel: 1, type: 'dhcp')
      resource_b = described_class.new({ name: 'net_b', lan_channel: 2 }.merge(static_params))
      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource_a)
      catalog.add_resource(resource_b)

      expect { resource_a.pre_run_check }.not_to raise_error
    end
  end
end
