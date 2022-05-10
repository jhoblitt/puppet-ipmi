# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi facts' do
  before(:each) do
    Facter.clear
    File.stubs(:executable?) # Stub all other calls
    Facter::Util::Resolution.stubs(:exec) # Catch all other calls
  end

  describe 'ipmi' do
    context 'when ipmitool present' do
      context 'with ipmi_* facts taken from channel 1' do
        before(:each) do
          ipmitool_output = <<-OUTPUT
          Set in Progress         : Set Complete
          Auth Type Support       :
          Auth Type Enable        : Callback :
          : User     :
          : Operator :
          : Admin    :
          : OEM      :
          IP Address Source       : DHCP Address
          IP Address              : 192.168.0.37
          Subnet Mask             : 255.255.255.0
          MAC Address             : 3c:a8:2a:9f:9a:92
          SNMP Community String   :
          BMC ARP Control         : ARP Responses Enabled, Gratuitous ARP Disabled
          Default Gateway IP      : 192.168.0.1
          802.1q VLAN ID          : Disabled
          802.1q VLAN Priority    : 0
          RMCP+ Cipher Suites     : 0,1,2,3
          Cipher Suite Priv Max   : XuuaXXXXXXXXXXX
          :     X=Cipher Suite Unused
          :     c=CALLBACK
          :     u=USER
          :     o=OPERATOR
          :     a=ADMIN
          :     O=OEM
          Bad Password Threshold  : Not Available
          OUTPUT
          Facter::Util::Resolution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
          Facter::Util::Resolution.expects(:exec).at_least(1).with('ipmitool lan print 1 2>&1').returns(ipmitool_output)
          (2..11).to_a.each do |mocked_channel|
            Facter::Util::Resolution.expects(:exec).at_least(1).with("ipmitool lan print #{mocked_channel} 2>&1").returns("Invalid channel: #{mocked_channel}")
          end
          Facter.fact(:kernel).stubs(:value).returns('Linux')
        end

        let(:facts) { { kernel: 'Linux' } }

        it do
          expect(Facter.value(:ipmi_ipaddress)).to eq('192.168.0.37')
        end

        it do
          expect(Facter.value(:ipmi_ipaddress_source)).to eq('DHCP Address')
        end

        it do
          expect(Facter.value(:ipmi_subnet_mask)).to eq('255.255.255.0')
        end

        it do
          expect(Facter.value(:ipmi_macaddress)).to eq('3c:a8:2a:9f:9a:92')
        end

        it do
          expect(Facter.value(:ipmi_gateway)).to eq('192.168.0.1')
        end
      end

      context 'when multiple channels' do
        before(:each) do
          ipmitool_2_output = <<-OUTPUT
          Set in Progress         : Set Complete
          Auth Type Support       :
          Auth Type Enable        : Callback :
          : User     :
          : Operator :
          : Admin    :
          : OEM      :
          IP Address Source       : DHCP Address
          IP Address              : 192.168.0.22
          Subnet Mask             : 255.255.255.0
          MAC Address             : c6:92:00:22:79:f3
          SNMP Community String   :
          BMC ARP Control         : ARP Responses Enabled, Gratuitous ARP Disabled
          Default Gateway IP      : 192.168.0.2
          802.1q VLAN ID          : Disabled
          802.1q VLAN Priority    : 0
          RMCP+ Cipher Suites     : 0,1,2,3
          Cipher Suite Priv Max   : XuuaXXXXXXXXXXX
          :     X=Cipher Suite Unused
          :     c=CALLBACK
          :     u=USER
          :     o=OPERATOR
          :     a=ADMIN
          :     O=OEM
          Bad Password Threshold  : Not Available
          OUTPUT

          ipmitool_3_output = <<-OUTPUT
          Set in Progress         : Set Complete
          Auth Type Support       :
          Auth Type Enable        : Callback :
          : User     :
          : Operator :
          : Admin    :
          : OEM      :
          IP Address Source       : DHCP Address
          IP Address              : 192.168.0.33
          Subnet Mask             : 255.255.255.0
          MAC Address             : 1a:16:97:fb:64:d8
          SNMP Community String   :
          BMC ARP Control         : ARP Responses Enabled, Gratuitous ARP Disabled
          Default Gateway IP      : 192.168.0.3
          802.1q VLAN ID          : Disabled
          802.1q VLAN Priority    : 0
          RMCP+ Cipher Suites     : 0,1,2,3
          Cipher Suite Priv Max   : XuuaXXXXXXXXXXX
          :     X=Cipher Suite Unused
          :     c=CALLBACK
          :     u=USER
          :     o=OPERATOR
          :     a=ADMIN
          :     O=OEM
          Bad Password Threshold  : Not Available
          OUTPUT

          Facter::Util::Resolution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
          Facter::Util::Resolution.expects(:exec).at_least(1).with('ipmitool lan print 2 2>&1').returns(ipmitool_2_output)
          Facter::Util::Resolution.expects(:exec).at_least(1).with('ipmitool lan print 3 2>&1').returns(ipmitool_3_output)
          Facter::Util::Resolution.expects(:exec).at_least(1).with('ipmitool lan print 1 2>&1').returns('Invalid channel: 1')
          (4..11).to_a.each do |mocked_channel|
            Facter::Util::Resolution.expects(:exec).at_least(1).with("ipmitool lan print #{mocked_channel} 2>&1").returns("Invalid channel: #{mocked_channel}")
          end
          Facter.fact(:kernel).stubs(:value).returns('Linux')
        end

        let(:facts) { { kernel: 'Linux' } }

        describe 'ipmi2_* facts' do
          it do
            expect(Facter.value(:ipmi2_gateway)).to eq('192.168.0.2')
          end

          it do
            expect(Facter.value(:ipmi2_ipaddress)).to eq('192.168.0.22')
          end

          it do
            expect(Facter.value(:ipmi2_ipaddress_source)).to eq('DHCP Address')
          end

          it do
            expect(Facter.value(:ipmi2_subnet_mask)).to eq('255.255.255.0')
          end

          it do
            expect(Facter.value(:ipmi2_macaddress)).to eq('c6:92:00:22:79:f3')
          end
        end

        describe 'ipmi3_* facts' do
          it do
            expect(Facter.value(:ipmi3_gateway)).to eq('192.168.0.3')
          end

          it do
            expect(Facter.value(:ipmi3_ipaddress)).to eq('192.168.0.33')
          end

          it do
            expect(Facter.value(:ipmi3_ipaddress_source)).to eq('DHCP Address')
          end

          it do
            expect(Facter.value(:ipmi3_subnet_mask)).to eq('255.255.255.0')
          end

          it do
            expect(Facter.value(:ipmi3_macaddress)).to eq('1a:16:97:fb:64:d8')
          end
        end
      end
    end
  end

  context 'when ipmitool not present' do
    before(:each) do
      Facter.fact(:kernel).stubs(:value).returns('Linux')
    end

    it do
      Facter::Util::Resolution.expects(:which).at_least(1).with('ipmitool').returns(false)
      expect(Facter.value(:ipmi_ipaddress)).to be_nil
    end
  end
end
