# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::network', type: :define do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:title) { 'example' }

      # Base facts without manufacturer — used by most existing tests.
      # Interface type tests override this via subject-level let(:facts).
      let(:facts) do
        facts.merge(
          {
            ipmitool_mc_info: { IPMI_Puppet_Service_Recommend: 'running' },
            ipmi: { default: { channel: 1 } },
          }
        )
      end

      describe 'when deploying as dhcp with minimal params' do
        let(:params) { { type: 'dhcp' } }

        it { is_expected.to contain_exec('ipmi_set_dhcp_1') }
        it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
      end

      describe 'when deploying as dhcp with all params' do
        let(:params) do
          {
            ip: '1.1.1.1',
            netmask: '255.255.255.0',
            gateway: '2.2.2.2',
            type: 'dhcp',
            lan_channel: 1,
          }
        end

        it { is_expected.to contain_exec('ipmi_set_dhcp_1') }
        it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
      end

      describe 'when deploying as static with minimal params' do
        let(:params) do
          {
            ip: '1.1.1.10',
            netmask: '255.255.255.0',
            gateway: '1.1.1.1',
            type: 'static',
          }
        end

        it { is_expected.to contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_ipaddr_1]') }
        it { is_expected.to contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_defgw_1]') }
        it { is_expected.to contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_netmask_1]') }
        it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
      end

      describe 'when deploying as static with all params' do
        let(:params) do
          {
            ip: '1.1.1.10',
            netmask: '255.255.255.0',
            gateway: '1.1.1.1',
            type: 'static',
            lan_channel: 2,
          }
        end

        it { is_expected.to contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_ipaddr_2]') }
        it { is_expected.to contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_defgw_2]') }
        it { is_expected.to contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_netmask_2]') }
        it { is_expected.not_to contain_exec('ipmi_set_interface_type_2') }
      end

      describe 'interface_type' do
        # Shared params for all interface_type tests — type itself is irrelevant
        # to interface configuration, so use dhcp to keep tests focused.
        let(:base_params) { { type: 'dhcp', lan_channel: 1 } }

        describe 'when manufacturer fact is absent' do
          let(:params) { base_params.merge(interface_type: 'dedicated') }

          # ipmitool_mc_info present but no Manufacturer Name key
          it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
        end

        describe 'when manufacturer is unknown' do
          let(:facts) do
            facts.merge(
              {
                ipmitool_mc_info: {
                  IPMI_Puppet_Service_Recommend: 'running',
                  'Manufacturer Name' => 'HPE',
                },
                ipmi: { default: { channel: 1 } },
              }
            )
          end
          let(:params) { base_params.merge(interface_type: 'dedicated') }

          it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
          it { is_expected.to compile.with_warnings }
        end

        describe 'Supermicro' do
          let(:facts) do
            facts.merge(
              {
                ipmitool_mc_info: {
                  IPMI_Puppet_Service_Recommend: 'running',
                  'Manufacturer Name' => 'Supermicro',
                },
                ipmi: { default: { channel: 1 } },
              }
            )
          end

          { 'dedicated' => 0, 'shared' => 1, 'failover' => 2 }.each do |iface_type, code|
            describe "interface_type => #{iface_type}" do
              let(:params) { base_params.merge(interface_type: iface_type) }

              it { is_expected.to contain_exec('ipmi_set_interface_type_1')
                .with_command("/usr/bin/ipmitool raw 0x30 0x70 0x0c 1 #{code}")
                .with_onlyif("/usr/bin/test $(/usr/bin/ipmitool raw 0x30 0x70 0x0c 0) -ne #{code}") }
            end
          end
        end

        describe 'Dell' do
          let(:facts) do
            facts.merge(
              {
                ipmitool_mc_info: {
                  IPMI_Puppet_Service_Recommend: 'running',
                  'Manufacturer Name' => 'Dell',
                },
                ipmi: { default: { channel: 1 } },
              }
            )
          end

          { 'dedicated' => 2, 'shared' => 0, 'failover' => 1 }.each do |iface_type, code|
            describe "interface_type => #{iface_type}" do
              let(:params) { base_params.merge(interface_type: iface_type) }

              it { is_expected.to contain_exec('ipmi_set_interface_type_1')
                .with_command("/usr/bin/ipmitool raw 0x30 0x24 #{code}")
                .with_onlyif("/usr/bin/test $(/usr/bin/ipmitool raw 0x30 0x25) -ne #{code}") }
            end
          end
        end

        describe 'when interface_type is undef' do
          let(:facts) do
            facts.merge(
              {
                ipmitool_mc_info: {
                  IPMI_Puppet_Service_Recommend: 'running',
                  'Manufacturer Name' => 'Supermicro',
                },
                ipmi: { default: { channel: 1 } },
              }
            )
          end
          let(:params) { base_params }

          # Manufacturer present but interface_type not requested — no exec created
          it { is_expected.not_to contain_exec('ipmi_set_interface_type_1') }
        end

        describe 'invalid interface_type value' do
          let(:params) { base_params.merge(interface_type: 'bonded') }

          it { is_expected.to compile.and_raise_error(%r{interface_type}) }
        end
      end
    end
  end
end
