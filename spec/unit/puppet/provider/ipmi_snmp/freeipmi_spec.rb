# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp).provider(:freeipmi) do
  let(:type) { Puppet::Type.type(:ipmi_snmp) }
  let(:pef_conf) do
    File.read('spec/fixtures/unit/puppet/provider/ipmi_snmp/pef_config_community.txt')
  end

  it_behaves_like 'command-confined provider', :pefconfig

  def resource_for(params)
    type.new({ name: 'test', provider: 'freeipmi' }.merge(params))
  end

  describe 'community property' do
    let(:provider) { resource_for(lan_channel: 1).provider }

    it 'returns the current community string' do
      provider.expects(:bmcconfig_exec)
              .with(['--checkout', '--section', 'Community_String', '--lan-channel-number', '1'])
              .returns(pef_conf)

      expect(provider.community).to eq('secret')
    end

    it 'sets the community string' do
      provider.expects(:bmcconfig_exec)
              .with(['--commit', '--key-pair', 'Community_String:Community_String=private', '--lan-channel-number', '1'], sensitive: false)

      provider.community = 'private'
    end

    it 'raises when the community string contains whitespace' do
      expect { provider.community = 'my community' }
        .to raise_error(Puppet::Error, %r{freeipmi cannot store a value containing whitespace})
    end
  end
end
