# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_network'

describe Puppet::Type.type(:ipmi_network).provider(:ipmitool) do
  let(:type) { Puppet::Type.type(:ipmi_network) }
  let(:lan_print) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_network/ipmitool_lan_print.txt')
  end

  it_behaves_like 'command-confined provider', :ipmitool

  def resource_for(params)
    type.new({ name: 'test', provider: 'ipmitool' }.merge(params))
  end

  describe 'property getters' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    before do
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(lan_print)
    end

    it 'returns type :static' do
      expect(provider.type).to eq(:static)
    end

    it 'returns the ip address' do
      expect(provider.ip).to eq('192.168.56.180')
    end

    it 'returns the netmask' do
      expect(provider.netmask).to eq('255.255.248.0')
    end

    it 'returns the gateway' do
      expect(provider.gateway).to eq('192.168.56.1')
    end
  end

  describe 'type getter' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'returns :dhcp when IP Address Source is DHCP' do
      dhcp_print = lan_print.gsub('Static Address', 'DHCP Address')
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(dhcp_print)

      expect(provider.type).to eq(:dhcp)
    end
  end

  describe 'property setters' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'sets type to dhcp' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipsrc dhcp])

      provider.type = :dhcp
    end

    it 'sets type to static' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipsrc static])

      provider.type = :static
    end

    it 're-applies static network settings after switching to static' do
      provider = resource_for(
        lan_channel: 1,
        type: :static,
        ip: '192.168.1.100',
        netmask: '255.255.255.0',
        gateway: '192.168.1.1',
      ).provider
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipsrc static])
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(lan_print).at_least_once
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipaddr 192.168.1.100])
      provider.expects(:ipmitool_exec).with(%w[lan set 1 netmask 255.255.255.0])
      provider.expects(:ipmitool_exec).with(%w[lan set 1 defgw ipaddr 192.168.1.1])

      provider.type = :static
    end

    it 'sets the ip address' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipaddr 192.168.1.100])

      provider.ip = '192.168.1.100'
    end

    it 'sets the netmask' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 netmask 255.255.255.0])

      provider.netmask = '255.255.255.0'
    end

    it 'sets the gateway' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 defgw ipaddr 192.168.1.1])

      provider.gateway = '192.168.1.1'
    end
  end

  describe 'lan print caching' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'calls ipmitool lan print only once per provider instance' do
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(lan_print).once

      provider.type
      provider.ip
      provider.netmask
      provider.gateway
    end

    it 'invalidates the cache after a write' do
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(lan_print).twice
      provider.expects(:ipmitool_exec).with(%w[lan set 1 ipaddr 192.168.1.100])

      provider.ip
      provider.ip = '192.168.1.100'
      provider.ip
    end
  end
end
