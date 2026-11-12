# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_network'

describe Puppet::Type.type(:ipmi_network).provider(:freeipmi) do
  let(:type) { Puppet::Type.type(:ipmi_network) }
  let(:lan_conf) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_network/bmc_config_lan_conf.txt')
  end

  it_behaves_like 'command-confined provider', :bmcconfig

  def resource_for(params)
    type.new({ name: 'test', provider: 'freeipmi' }.merge(params))
  end

  describe 'property getters' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    before do
      provider.expects(:bmcconfig_exec)
              .with(%w[--checkout --section Lan_Conf --lan-channel-number 1])
              .returns(lan_conf)
    end

    it 'returns type :static' do
      expect(provider.type).to eq(:static)
    end

    it 'returns the ip address' do
      expect(provider.ip).to eq('192.168.57.34')
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

    it 'returns :dhcp when IP_Address_Source is Use_DHCP' do
      dhcp_conf = lan_conf.gsub('Static', 'Use_DHCP')
      provider.expects(:bmcconfig_exec)
              .with(%w[--checkout --section Lan_Conf --lan-channel-number 1])
              .returns(dhcp_conf)

      expect(provider.type).to eq(:dhcp)
    end
  end

  describe 'property setters' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'sets type to dhcp' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address_Source=Use_DHCP --lan-channel-number 1], sensitive: false)

      provider.type = :dhcp
    end

    it 'sets type to static' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address_Source=Static --lan-channel-number 1], sensitive: false)

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
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address_Source=Static --lan-channel-number 1], sensitive: false)
      provider.expects(:bmcconfig_exec)
              .with(%w[--checkout --section Lan_Conf --lan-channel-number 1])
              .returns(lan_conf)
              .at_least_once
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address=192.168.1.100 --lan-channel-number 1], sensitive: false)
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:Subnet_Mask=255.255.255.0 --lan-channel-number 1], sensitive: false)
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:Default_Gateway_IP_Address=192.168.1.1 --lan-channel-number 1], sensitive: false)

      provider.type = :static
    end

    it 'sets the ip address' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address=192.168.1.100 --lan-channel-number 1], sensitive: false)

      provider.ip = '192.168.1.100'
    end

    it 'sets the netmask' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:Subnet_Mask=255.255.255.0 --lan-channel-number 1], sensitive: false)

      provider.netmask = '255.255.255.0'
    end

    it 'sets the gateway' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:Default_Gateway_IP_Address=192.168.1.1 --lan-channel-number 1], sensitive: false)

      provider.gateway = '192.168.1.1'
    end
  end

  describe '#bmc_config_get and #bmc_config_set' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'reads a key from a checked-out section' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--checkout --section Lan_Conf --lan-channel-number 1])
              .returns(lan_conf)

      expect(provider.bmc_config_get('Lan_Conf', 'IP_Address', channel: 1)).to eq('192.168.57.34')
    end

    it 'returns nil for a missing key' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--checkout --section Lan_Conf --lan-channel-number 1])
              .returns(lan_conf)

      expect(provider.bmc_config_get('Lan_Conf', 'No_Such_Key', channel: 1)).to be_nil
    end

    it 'commits a key/value pair with an optional channel' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:IP_Address=192.168.1.100 --lan-channel-number 1], sensitive: false)

      provider.bmc_config_set('Lan_Conf', 'IP_Address', '192.168.1.100', channel: 1)
    end

    it 'passes the sensitive flag through' do
      provider.expects(:bmcconfig_exec)
              .with(%w[--commit --key-pair Lan_Conf:Secret=hidden], sensitive: true)

      provider.bmc_config_set('Lan_Conf', 'Secret', 'hidden', sensitive: true)
    end
  end

  describe 'bmc-config section caching' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'checks out Lan_Conf only once per provider instance' do
      provider.expects(:bmcconfig_exec)
              .with(['--checkout', '--section', 'Lan_Conf', '--lan-channel-number', '1'])
              .returns(lan_conf)
              .once

      provider.type
      provider.ip
      provider.netmask
      provider.gateway
    end

    it 'invalidates the section cache after a write' do
      provider.expects(:bmcconfig_exec)
              .with(['--checkout', '--section', 'Lan_Conf', '--lan-channel-number', '1'])
              .returns(lan_conf)
              .twice
      provider.expects(:bmcconfig_exec)
              .with(['--commit', '--key-pair', 'Lan_Conf:IP_Address=192.168.1.100', '--lan-channel-number', '1'], sensitive: false)

      provider.ip
      provider.ip = '192.168.1.100'
      provider.ip
    end
  end
end
