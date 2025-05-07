# frozen_string_literal: true

require 'spec_helper'
require 'facter'
require 'facter/ipmitool_mc_info'

describe 'ipmitool_mc_info', type: :fact do
  subject(:fact) { Facter.fact(:ipmitool_mc_info) }

  before do
    # perform any action that should be run before every test
    Facter.clear
    Facter.fact(:kernel).stubs(:value).returns('Linux')
  end

  context 'with no ipmitool fact' do
    before do
      Facter.fact(:ipmitool).stubs(:value).returns(nil)
    end

    it do
      expect(fact.value).to eq({ 'IPMI_Puppet_Service_Recommend' => 'stopped' })
    end
  end

  context 'with detailed output' do
    before do
      Facter.fact(:ipmitool).stubs(:value).returns(
        {
          fru: {},
          mc_info: {
            'Device ID' => '32',
            'Device Revision' => '1',
            'Firmware Revision' => '2.49',
            'IPMI Version' => '2.0',
            'IPMI_Puppet_Service_Recommend' => 'running',
            'Manufacturer ID' => '10876',
            'Manufacturer Name' => 'Supermicro',
            'Product ID' => '43707 (0xaabb)',
            'Product Name' => 'Unknown (0xAABB)',
            'Device Available' => 'yes',
            'Provides Device SDRs' => 'no',
          }
        }
      )
    end

    it do
      expect(fact.value).to eq(
        {
          'Device ID' => '32',
          'Device Revision' => '1',
          'Firmware Revision' => '2.49',
          'IPMI Version' => '2.0',
          'IPMI_Puppet_Service_Recommend' => 'running',
          'Manufacturer ID' => '10876',
          'Manufacturer Name' => 'Supermicro',
          'Product ID' => '43707 (0xaabb)',
          'Product Name' => 'Unknown (0xAABB)',
          'Device Available' => 'yes',
          'Provides Device SDRs' => 'no',
        }
      )
    end
  end
end
