# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp).provider(:ipmitool) do
  let(:type) { Puppet::Type.type(:ipmi_snmp) }
  let(:lan_print) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_network/ipmitool_lan_print.txt')
  end

  it_behaves_like 'command-confined provider', :ipmitool

  def resource_for(params)
    type.new({ name: 'test', provider: 'ipmitool' }.merge(params))
  end

  describe 'community property' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'returns the current community string' do
      provider.expects(:ipmitool_exec).with(%w[lan print 1]).returns(lan_print)

      expect(provider.community).to eq('public')
    end

    it 'sets the community string' do
      provider.expects(:ipmitool_exec).with(%w[lan set 1 snmp secret])

      provider.community = 'secret'
    end
  end
end
