# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::network' do
  let(:title) { 'test_net' }
  let(:params) { {} }

  # Puppet::Util::Log.level = :debug
  # Puppet::Util::Log.newdestination(:console)
  let(:pre_condition) { 'include ipmi' }

  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts }

      describe 'check default config' do
        it { is_expected.to compile.with_all_deps }
        it do
          is_expected.to contain_exec('ipmi_set_dhcp_1').with(
            command: '/usr/bin/ipmitool lan set 1 ipsrc dhcp',
            onlyif: "/usr/bin/test $(ipmitool lan print 1 | grep 'IP Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 0",
          )
        end
      end
      describe 'Change Defaults' do
        context 'ip' do
          before(:each) { params.merge!(type: 'static', ip: '192.0.2.42') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_ipaddr_1').with(
              command: '/usr/bin/ipmitool lan set 1 ipaddr 192.0.2.42',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'IP Address  ' | sed -e 's/.* : //g')\" != \"192.0.2.42\"",
            )
          end
        end
        context 'netmask' do
          before(:each) { params.merge!(type: 'static', netmask: '255.255.255.192') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_netmask_1').with(
              command: '/usr/bin/ipmitool lan set 1 netmask 255.255.255.192',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'Subnet Mask' | sed -e 's/.* : //g')\" != \"255.255.255.192\"",
            )
          end
        end
        context 'gateway' do
          before(:each) { params.merge!(type: 'static', gateway: '192.0.2.254') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_defgw_1').with(
              command: '/usr/bin/ipmitool lan set 1 defgw ipaddr 192.0.2.254',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'Default Gateway IP' | sed -e 's/.* : //g')\" != \"192.0.2.254\"",
            )
          end
        end
        context 'type' do
          before(:each) { params.merge!(type: 'static') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_static_1').with(
              command: '/usr/bin/ipmitool lan set 1 ipsrc static',
              onlyif: "/usr/bin/test $(ipmitool lan print 1 | grep 'IP Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 1",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_ipaddr_1').with(
              command: '/usr/bin/ipmitool lan set 1 ipaddr 0.0.0.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'IP Address  ' | sed -e 's/.* : //g')\" != \"0.0.0.0\"",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_defgw_1').with(
              command: '/usr/bin/ipmitool lan set 1 defgw ipaddr 0.0.0.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'Default Gateway IP' | sed -e 's/.* : //g')\" != \"0.0.0.0\"",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_netmask_1').with(
              command: '/usr/bin/ipmitool lan set 1 netmask 255.255.255.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'Subnet Mask' | sed -e 's/.* : //g')\" != \"255.255.255.0\"",
            )
          end
        end
        context 'lan_channel' do
          before(:each) { params.merge!(type: 'static', lan_channel: 42) }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_static_42').with(
              command: '/usr/bin/ipmitool lan set 42 ipsrc static',
              onlyif: "/usr/bin/test $(ipmitool lan print 42 | grep 'IP Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 1",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_ipaddr_42').with(
              command: '/usr/bin/ipmitool lan set 42 ipaddr 0.0.0.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 42 | grep 'IP Address  ' | sed -e 's/.* : //g')\" != \"0.0.0.0\"",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_defgw_42').with(
              command: '/usr/bin/ipmitool lan set 42 defgw ipaddr 0.0.0.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 42 | grep 'Default Gateway IP' | sed -e 's/.* : //g')\" != \"0.0.0.0\"",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_set_netmask_42').with(
              command: '/usr/bin/ipmitool lan set 42 netmask 255.255.255.0',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 42 | grep 'Subnet Mask' | sed -e 's/.* : //g')\" != \"255.255.255.0\"",
            )
          end
        end
      end
      describe 'check bad type' do
        context 'ip' do
          before(:each) { params.merge!(ip: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'netmask' do
          before(:each) { params.merge!(netmask: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'gateway' do
          before(:each) { params.merge!(gateway: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'type' do
          before(:each) { params.merge!(type: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'lan_channel' do
          before(:each) { params.merge!(lan_channel: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
      end
    end
  end
end
