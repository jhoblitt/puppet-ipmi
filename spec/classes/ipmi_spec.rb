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
end

describe 'ipmi', type: :class do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts.merge(ipmitool_mc_info: { IPMI_Puppet_Service_Recommend: 'running' }) }

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

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with service_ensure => running' do
        let(:params) { { service_ensure: 'running' } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with service_ensure => stopped' do
        let(:params) { { service_ensure: 'stopped' } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'stopped',
            enable: false
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with ipmievd_service_ensure => running' do
        let(:params) { { ipmievd_service_ensure: 'running' } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'running',
            enable: true
          )
        end
      end

      context 'with ipmievd_service_ensure => stopped' do
        let(:params) { { ipmievd_service_ensure: 'stopped' } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with watchdog => true' do
        let(:params) { { watchdog: true } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG yes',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with watchdog => false' do
        let(:params) { { watchdog: false } }

        it_behaves_like 'installs packages', facts

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: [
              'set IPMI_WATCHDOG no',
            ]
          )
        end

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'running',
            enable: true
          )
        end

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false
          )
        end
      end

      context 'with defines' do
        let(:params) do
          {
            users: { newuser: { user: 'newuser', password: 'password' } },
            networks: { dhcp: {} },
            snmps: { snmp1: { snmp: 'secret', lan_channel: 1 } }
          }
        end

        it { is_expected.to compile.with_all_deps }
      end
    end
  end
end
