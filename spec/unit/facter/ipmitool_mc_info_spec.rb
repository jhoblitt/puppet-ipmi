# frozen_string_literal: true

require 'spec_helper'
require 'facter'
require 'facter/ipmitool_mc_info'

describe 'ipmitool_mc_info', type: :fact do
  subject(:fact) { Facter.fact(:ipmitool_mc_info) }

  before :each do
    # perform any action that should be run before every test
    Facter.clear
  end

  let(:detailed_output) do
    <<~SAMPLE
Device ID                 : 32
Device Revision           : 1
Firmware Revision         : 2.49
IPMI Version              : 2.0
Manufacturer ID           : 10876
Manufacturer Name         : Supermicro
Product ID                : 43707 (0xaabb)
Product Name              : Unknown (0xAABB)
Device Available          : yes
Provides Device SDRs      : no
Additional Device Support :
    Sensor Device
    SDR Repository Device
    SEL Device
    FRU Inventory Device
    IPMB Event Receiver
    IPMB Event Generator
    Chassis Device
Aux Firmware Rev Info     :
    0x00
    0x00
    0x00
    0x00
    SAMPLE
  end

  context 'with no ipmitool' do
    before :each do
      Facter::Util::Resolution.expects(:which).at_least(1).with('ipmitool').returns(nil)
      Facter::Util::Resolution.expects(:exec).with('ipmitool mc info 2>/dev/null').never
    end

    it do
      expect(fact.value).to eq({ 'IPMI_Puppet_Service_Recommend' => 'stopped' })
    end
  end

  context 'with detailed output' do
    before :each do
      Facter::Util::Resolution.expects(:which).with('ipmitool').returns('ipmitool')
      Facter::Util::Resolution.expects(:exec).with('ipmitool mc info 2>/dev/null').returns(detailed_output)
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
        },
      )
    end
  end
end
