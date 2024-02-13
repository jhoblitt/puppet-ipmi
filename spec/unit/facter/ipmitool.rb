# frozen_string_literal: true

require 'spec_helper'
require 'facter'

describe 'ipmitool', type: :fact do
  subject(:fact) { Facter.fact(:ipmitool) }

  before do
    # perform any action that should be run before every test
    Facter.clear
    Facter.fact(:kernel).stubs(:value).returns('Linux')
    Facter.fact(:is_virtual).stubs(:value).returns(false)
  end

  let(:fru_output) do
    <<~OUTPUT
      Board Mfg Date        : Tue Mar  3 21:43:00 2015
      Board Mfg             : DELL
      Board Product         : PowerEdge R220
      Board Serial          : 000000
      Board Part Number     : 0DRXF5A04
      Product Manufacturer  : DELL
      Product Name          : Test
      Product Extra         : 000000
    OUTPUT
  end
  let(:mc_output) do
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
    before do
      Facter::Util::Resolution.expects(:which).at_least(1).with('ipmitool').returns(nil)
      Facter::Util::Resolution.expects(:exec).with('ipmitool mc info 2>/dev/null').never
      Facter::Util::Resolution.expects(:exec).with('ipmitool fru print 0 2>/dev/null').never
    end

    it do
      expect(fact.value).to eq({ 'fru' => {}, 'mc_info' => { 'IPMI_Puppet_Service_Recommend' => 'stopped' } })
    end
  end

  context 'with detailed output' do
    before do
      Facter::Util::Resolution.expects(:which).with('ipmitool').returns(true)
      Facter::Util::Resolution.expects(:exec).with('ipmitool mc info 2>/dev/null').returns(mc_output)
      Facter::Util::Resolution.expects(:exec).with('ipmitool fru print 0 2>/dev/null').returns(fru_output)
    end

    it do
      expect(fact.value).to eq(
        {
          'mc_info' => {
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
          'fru' => {
            'board_mfg_date' => 'Tue Mar  3 21:43:00 2015',
            'board_mfg' => 'DELL',
            'board_product' => 'PowerEdge R220',
            'board_serial' => '000000',
            'board_part_number' => '0DRXF5A04',
            'product_manufacturer' => 'DELL',
            'product_name' => 'Test',
            'product_extra' => '000000',
          }
        }
      )
    end
  end
end
