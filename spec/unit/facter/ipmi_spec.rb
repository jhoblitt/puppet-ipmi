# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi facts' do
  before do
    Facter.clear
    File.stubs(:executable?) # Stub all other calls
    Facter::Core::Execution.stubs(:execute) # Catch all other calls
  end

  describe 'ipmi' do
    context 'when ipmitool present' do
      context 'with ipmi_* facts taken from channel 1' do
        before do
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
          ipmitool_user_output = <<-USEROUTPUT
          ID  Name	     Callin  Link Auth	IPMI Msg   Channel Priv Limit
          1                    true    false      true       ADMINISTRATOR
          2   admin            true    false      true       ADMINISTRATOR
          3   foo_123_bar      true    false      true       ADMINISTRATOR
          4   (Empty User)     true    false      false      NO ACCESS
          5   (Empty User)     true    false      false      NO ACCESS
          6   (Empty User)     true    false      false      NO ACCESS
          7   (Empty User)     true    false      false      NO ACCESS
          8   (Empty User)     true    false      false      NO ACCESS
          9   (Empty User)     true    false      false      NO ACCESS
          10  (Empty User)     true    false      false      NO ACCESS
          11  (Empty User)     true    false      false      NO ACCESS
          12  foobar           true    false      true       USER
          USEROUTPUT
          Facter::Core::Execution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 1 2>&1', on_fail: '').returns(ipmitool_output)
          (2..11).to_a.each do |mocked_channel|
            Facter::Core::Execution.expects(:execute).at_least(1).with("ipmitool lan print #{mocked_channel} 2>&1", on_fail: '').returns("Invalid channel: #{mocked_channel}")
          end
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool user list 1 2>&1', on_fail: '').returns(ipmitool_user_output)
          kernel_fact = mock('kernel_fact')
          kernel_fact.stubs(:value).returns('Linux')
          Facter.stubs(:fact).with(:kernel).returns(kernel_fact)
        end

        let(:facts) { { kernel: 'Linux' } }

        it do
          expect(Facter.value('ipmi.1.users.1.id')).to eq(1)
          expect(Facter.value('ipmi.1.users.1.name')).to eq('')
          expect(Facter.value('ipmi.1.users.1.privilege')).to eq('ADMINISTRATOR')
        end

        it do
          expect(Facter.value('ipmi.1.users.12.id')).to eq(12)
          expect(Facter.value('ipmi.1.users.12.name')).to eq('foobar')
          expect(Facter.value('ipmi.1.users.12.privilege')).to eq('USER')
        end

        it do
          expect(Facter.value('ipmi.1.users.4.id')).to eq(4)
          expect(Facter.value('ipmi.1.users.4.name')).to eq('(Empty User)')
          expect(Facter.value('ipmi.1.users.4.privilege')).to eq('NO ACCESS')
        end

        it do
          expect(Facter.value(:ipmi_ipaddress)).to eq('192.168.0.37')
          expect(Facter.value('ipmi.default.ipaddress')).to eq('192.168.0.37')
          expect(Facter.value('ipmi.1.ipaddress')).to eq('192.168.0.37')
        end

        it do
          expect(Facter.value(:ipmi_ipaddress_source)).to eq('DHCP Address')
          expect(Facter.value('ipmi.default.ipaddress_source')).to eq('DHCP Address')
          expect(Facter.value('ipmi.1.ipaddress_source')).to eq('DHCP Address')
        end

        it do
          expect(Facter.value(:ipmi_subnet_mask)).to eq('255.255.255.0')
          expect(Facter.value('ipmi.default.subnet_mask')).to eq('255.255.255.0')
          expect(Facter.value('ipmi.1.subnet_mask')).to eq('255.255.255.0')
        end

        it do
          expect(Facter.value(:ipmi_macaddress)).to eq('3c:a8:2a:9f:9a:92')
          expect(Facter.value('ipmi.default.macaddress')).to eq('3c:a8:2a:9f:9a:92')
          expect(Facter.value('ipmi.1.macaddress')).to eq('3c:a8:2a:9f:9a:92')
        end

        it do
          expect(Facter.value(:ipmi_gateway)).to eq('192.168.0.1')
          expect(Facter.value('ipmi.default.gateway')).to eq('192.168.0.1')
          expect(Facter.value('ipmi.1.gateway')).to eq('192.168.0.1')
        end
      end

      context 'when multiple channels' do
        before do
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
          ipmitool_user_output = <<-USEROUTPUT
          ID  Name	     Callin  Link Auth	IPMI Msg   Channel Priv Limit
          1                    true    false      true       ADMINISTRATOR
          2   admin            true    false      true       ADMINISTRATOR
          3   foo_123_bar      true    false      true       ADMINISTRATOR
          4   (Empty User)     true    false      false      NO ACCESS
          5   (Empty User)     true    false      false      NO ACCESS
          6   (Empty User)     true    false      false      NO ACCESS
          7   (Empty User)     true    false      false      NO ACCESS
          8   (Empty User)     true    false      false      NO ACCESS
          9   (Empty User)     true    false      false      NO ACCESS
          10  (Empty User)     true    false      false      NO ACCESS
          11  (Empty User)     true    false      false      NO ACCESS
          12  foobar           true    false      true       USER
          USEROUTPUT
          Facter::Core::Execution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 2 2>&1', on_fail: '').returns(ipmitool_2_output)
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 3 2>&1', on_fail: '').returns(ipmitool_3_output)
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 1 2>&1', on_fail: '').returns('Invalid channel: 1')
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool user list 2 2>&1', on_fail: '').returns(ipmitool_user_output)
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool user list 3 2>&1', on_fail: '').returns(ipmitool_user_output)
          (4..11).to_a.each do |mocked_channel|
            Facter::Core::Execution.expects(:execute).at_least(1).with("ipmitool lan print #{mocked_channel} 2>&1", on_fail: '').returns("Invalid channel: #{mocked_channel}")
          end
          kernel_fact = mock('kernel_fact')
          kernel_fact.stubs(:value).returns('Linux')
          Facter.stubs(:fact).with(:kernel).returns(kernel_fact)
        end

        let(:facts) { { kernel: 'Linux' } }

        describe 'ipmi2_* facts' do
          it do
            expect(Facter.value('ipmi.default.gateway')).to eq('192.168.0.2')
            expect(Facter.value('ipmi.2.gateway')).to eq('192.168.0.2')
          end

          it do
            expect(Facter.value('ipmi.default.ipaddress')).to eq('192.168.0.22')
            expect(Facter.value('ipmi.2.ipaddress')).to eq('192.168.0.22')
          end

          it do
            expect(Facter.value('ipmi.default.ipaddress_source')).to eq('DHCP Address')
            expect(Facter.value('ipmi.2.ipaddress_source')).to eq('DHCP Address')
          end

          it do
            expect(Facter.value('ipmi.default.subnet_mask')).to eq('255.255.255.0')
            expect(Facter.value('ipmi.2.subnet_mask')).to eq('255.255.255.0')
          end

          it do
            expect(Facter.value('ipmi.default.macaddress')).to eq('c6:92:00:22:79:f3')
            expect(Facter.value('ipmi.2.macaddress')).to eq('c6:92:00:22:79:f3')
          end
        end

        describe 'ipmi3_* facts' do
          it do
            expect(Facter.value('ipmi.3.gateway')).to eq('192.168.0.3')
          end

          it do
            expect(Facter.value('ipmi.3.ipaddress')).to eq('192.168.0.33')
          end

          it do
            expect(Facter.value('ipmi.3.ipaddress_source')).to eq('DHCP Address')
          end

          it do
            expect(Facter.value('ipmi.3.subnet_mask')).to eq('255.255.255.0')
          end

          it do
            expect(Facter.value('ipmi.3.macaddress')).to eq('1a:16:97:fb:64:d8')
          end
        end
      end

      context 'when multiple IPMI devices exist' do
        before do
          ipmitool_1_output = <<-OUTPUT
          IP Address              : 192.168.1.11
          Subnet Mask             : 255.255.255.0
          MAC Address             : aa:aa:aa:aa:aa:aa
          Default Gateway IP      : 192.168.1.1
          IP Address Source       : Static Address
          OUTPUT
          ipmitool_2_output = <<-OUTPUT
          IP Address              : 192.168.2.22
          Subnet Mask             : 255.255.255.0
          MAC Address             : bb:bb:bb:bb:bb:bb
          Default Gateway IP      : 192.168.2.1
          IP Address Source       : Static Address
          OUTPUT
          ipmitool_user_output = <<-USEROUTPUT
          ID  Name         Callin  Link Auth	IPMI Msg   Channel Priv Limit
          2   admin        true    false      true       ADMINISTRATOR
          USEROUTPUT
          Facter::Core::Execution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 1 2>&1', on_fail: '').returns(ipmitool_1_output)
          Facter::Core::Execution.expects(:execute).at_least(1).with('ipmitool lan print 2 2>&1', on_fail: '').returns(ipmitool_2_output)
          (3..11).to_a.each do |mocked_channel|
            Facter::Core::Execution.expects(:execute).at_least(1).with("ipmitool lan print #{mocked_channel} 2>&1", on_fail: '').returns("Invalid channel: #{mocked_channel}")
          end
          Facter::Core::Execution.stubs(:execute).with('ipmitool user list 1 2>&1', on_fail: '').returns(ipmitool_user_output)
          Facter::Core::Execution.stubs(:execute).with('ipmitool user list 2 2>&1', on_fail: '').returns(ipmitool_user_output)
          kernel_fact = mock('kernel_fact')
          kernel_fact.stubs(:value).returns('Linux')
          Facter.stubs(:fact).with(:kernel).returns(kernel_fact)
        end

        let(:facts) { { kernel: 'Linux' } }

        it 'exposes the first device as the Foreman-compatible flat facts' do
          expect(Facter.value(:ipmi_ipaddress)).to eq('192.168.1.11')
          expect(Facter.value(:ipmi_ipaddress_source)).to eq('Static Address')
          expect(Facter.value(:ipmi_subnet_mask)).to eq('255.255.255.0')
          expect(Facter.value(:ipmi_macaddress)).to eq('aa:aa:aa:aa:aa:aa')
          expect(Facter.value(:ipmi_gateway)).to eq('192.168.1.1')
        end

        it 'still exposes each device separately in the structured fact' do
          expect(Facter.value(:ipmi)['default']['ipaddress']).to eq('192.168.1.11')
          expect(Facter.value(:ipmi)['1']['gateway']).to eq('192.168.1.1')
          expect(Facter.value(:ipmi)['2']['ipaddress']).to eq('192.168.2.22')
          expect(Facter.value(:ipmi)['2']['macaddress']).to eq('bb:bb:bb:bb:bb:bb')
        end
      end
    end

    context 'when the BMC command degrades to empty output' do
      before do
        Facter::Core::Execution.expects(:which).at_least(1).with('ipmitool').returns('/usr/bin/ipmitool')
        # execute is called with on_fail: '' so a wedged BMC (300 s timeout), a
        # non-zero exit, or a missing binary degrades to empty output instead of
        # raising ExecutionFailure. Without that option, a wedged BMC would raise
        # mid-load and abort the rest of the fact file.
        Facter::Core::Execution.stubs(:execute).returns('')
        kernel_fact = mock('kernel_fact')
        kernel_fact.stubs(:value).returns('Linux')
        Facter.stubs(:fact).with(:kernel).returns(kernel_fact)
      end

      it do
        expect { Facter.value(:ipmi_ipaddress) }.not_to raise_error
        expect(Facter.value(:ipmi_ipaddress)).to be_nil
      end
    end
  end

  context 'when ipmitool not present' do
    before do
      kernel_fact = mock('kernel_fact')
      kernel_fact.stubs(:value).returns('Linux')
      Facter.stubs(:fact).with(:kernel).returns(kernel_fact)
    end

    it do
      Facter::Core::Execution.expects(:which).at_least(1).with('ipmitool').returns(false)
      expect(Facter.value(:ipmi_ipaddress)).to be_nil
      expect(Facter.value(:ipmi)).to be_empty
    end
  end
end
