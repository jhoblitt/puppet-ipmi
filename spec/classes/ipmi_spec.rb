# frozen_string_literal: true

require 'spec_helper'

shared_examples 'installs packages' do |facts|
  case facts[:os]['family']
  when 'RedHat'
    packages = %w[
      OpenIPMI
      ipmitool
    ]
  when 'Debian'
    packages = %w[
      openipmi
      ipmitool
    ]
  end

  packages.each do |p|
    it { is_expected.to contain_package(p) }
  end

  it { is_expected.to contain_class('ipmi::install') }
end

shared_examples 'contains ipmi::service' do
  it { is_expected.to contain_class('ipmi::service') }
  it { is_expected.to contain_class('ipmi::service::ipmi') }
  it { is_expected.to contain_class('ipmi::service::ipmievd') }
  it { is_expected.to contain_class('ipmi::config').that_notifies('Class[ipmi::service]') }
end

describe 'ipmi', type: :class do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts.merge(
          {
            ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
            ipmi: { default: { channel: 1 } },
          },
        )
      end

      case facts[:os]['family']
      when 'RedHat'
        let(:config_file) { '/etc/sysconfig/ipmi' }
        let(:service_name) { 'ipmi' }
      when 'Debian'
        let(:config_file) { '/etc/default/ipmi' }
        let(:service_name) { 'openipmi' }
      end

      it { is_expected.to compile.with_all_deps }

      context 'with no params' do
        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it { is_expected.to contain_class('ipmi::install') }
        it { is_expected.to contain_class('ipmi::config') }
        it { is_expected.to contain_class('ipmi::service::ipmi') }
        it { is_expected.to contain_class('ipmi::service::ipmievd') }

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with service_ensure => running' do
        let(:params) { { service_ensure: 'running' } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with service_ensure => stopped' do
        let(:params) { { service_ensure: 'stopped' } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'stopped',
            enable: false,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with ipmievd_service_ensure => running' do
        let(:params) { { ipmievd_service_ensure: 'running' } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'running',
            enable: true,
          )
        end
      end

      context 'with ipmievd_service_ensure => stopped' do
        let(:params) { { ipmievd_service_ensure: 'stopped' } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with watchdog => true' do
        let(:params) { { watchdog: true } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG yes',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with watchdog => false' do
        let(:params) { { watchdog: false } }

        it_behaves_like 'installs packages', facts
        it_behaves_like 'contains ipmi::service'

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ],
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with native resources' do
        let(:params) do
          {
            users: { newuser: { password: 'password' } },
            networks: { dhcp: {} },
            snmps: { snmp1: { community: 'secret', lan_channel: 1 } },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_user('newuser') }
        it { is_expected.to contain_ipmi_network('dhcp') }
        it { is_expected.to contain_ipmi_snmp('snmp1') }

        it_behaves_like 'contains ipmi::service'
      end

      context 'with default_channel set' do
        let(:params) do
          {
            default_channel: 8,
            users: { newuser: { password: 'password' } },
            networks: { dhcp: {} },
            snmps: { snmp1: { community: 'secret' } },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_user('newuser').with_channel(8) }
        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(8) }
        it { is_expected.to contain_ipmi_snmp('snmp1').with_lan_channel(8) }
      end

      context 'with a numeric LAN title and an explicit default_channel' do
        let(:facts) do
          super().merge(ipmi: { default: { channel: 3 } })
        end
        let(:params) do
          {
            default_channel: 8,
            networks: { '4' => {} },
            snmps: { '5' => { community: 'secret' } },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_network('4').with_lan_channel(8) }
        it { is_expected.to contain_ipmi_snmp('5').with_lan_channel(8) }
      end

      context 'with a node fact channel but no default_channel parameter' do
        let(:facts) do
          super().merge(ipmi: { default: { channel: 3 } })
        end
        let(:params) do
          {
            users: { newuser: { password: 'password' } },
            networks: { dhcp: {}, '4' => {} },
            snmps: { snmp1: { community: 'secret' } },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_user('newuser').with_channel(3) }
        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(3) }
        it { is_expected.to contain_ipmi_network('4').with_lan_channel(4) }
        it { is_expected.to contain_ipmi_snmp('snmp1').with_lan_channel(3) }
      end

      context 'with a malformed node fact channel' do
        let(:facts) do
          super().merge(ipmi: { default: { channel: 'invalid' } })
        end
        let(:params) { { users: { newuser: { password: 'password' } }, networks: { dhcp: {} } } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_user('newuser').with_channel(1) }
        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(1) }
      end

      context 'with default_channel and explicit channels' do
        let(:params) do
          {
            default_channel: 8,
            users: { newuser: { username: 'newuser', password: 'password', channel: 3 } },
            networks: { dhcp: { lan_channel: 2 } },
            snmps: { snmp1: { community: 'secret', lan_channel: 1 } },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_ipmi_user('newuser').with_channel(3) }
        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(2) }
        it { is_expected.to contain_ipmi_snmp('snmp1').with_lan_channel(1) }
      end

      context 'with ipmievd_service_name' do
        let(:params) { { ipmievd_service_name: 'custom_ipmievd' } }

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_service('custom_ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end

        it { is_expected.not_to contain_service('ipmievd') }
      end

      context 'with service_manage => false' do
        let(:params) { { service_manage: false } }

        it { is_expected.to compile.with_all_deps }

        # the ipmi service is left unmanaged
        it { is_expected.not_to contain_service(service_name) }

        # config/install are still managed
        it_behaves_like 'installs packages', facts

        # the companion ipmievd daemon is still managed
        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with the ipmi.default.channel fact set to 2' do
        let(:facts) { super().merge(ipmi: { default: { channel: 2 } }) }
        let(:params) { { networks: { dhcp: {} } } }

        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(2) }
      end

      context 'without the ipmi fact' do
        let(:facts) { super().except(:ipmi) }
        let(:params) { { networks: { dhcp: {} } } }

        it { is_expected.to contain_ipmi_network('dhcp').with_lan_channel(1) }
      end
    end
  end
end
