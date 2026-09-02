# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_network'

describe Puppet::Type.type(:ipmi_network) do
  describe 'when validating attributes' do
    %i[name lan_channel ipmitool_cmd bmcconfig_cmd].each do |param|
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
      resource = described_class.new(name: 'mynetwork')
      expect(resource[:lan_channel]).to eq(1)
    end

    it 'derives lan_channel from integer title' do
      resource = described_class.new(name: '3')
      expect(resource[:lan_channel]).to eq(3)
    end

    it 'accepts dhcp as type' do
      resource = described_class.new(name: 'test', type: 'dhcp')
      expect(resource[:type]).to eq(:dhcp)
    end

    it 'accepts static as type' do
      resource = described_class.new(name: 'test', type: 'static')
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
      resource = described_class.new(name: 'test', ip: '192.168.1.1')
      expect(resource[:ip]).to eq('192.168.1.1')
    end
  end
end
