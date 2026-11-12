# frozen_string_literal: true

require 'spec_helper'

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
      when 'Debian'
        let(:config_file) { '/etc/default/ipmi' }
      end

      context 'with defaults' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('ipmi::watchdog') }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi').with(enable: false) }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: false) }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG no']) }
        it { is_expected.not_to contain_class('ipmi::watchdog::kmod') }
      end

      context 'with watchdog => true' do
        let(:params) { { watchdog: true } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi').with(enable: true) }
        it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: true) }

        it do
          is_expected.to contain_augeas('ipmi_watchdog').with(
            context: "/files#{config_file}",
            changes: ['set IPMI_WATCHDOG yes'],
          )
        end

        it { is_expected.to contain_class('ipmi::watchdog::kmod') }
        it { is_expected.to contain_kmod__load('ipmi_watchdog') }
        it { is_expected.not_to contain_kmod__option('ipmi_watchdog_timeout') }
      end

      context 'with watchdog_timeout => 0' do
        let(:params) { { watchdog: true, watchdog_timeout: 0 } }

        it { is_expected.not_to contain_kmod__option('ipmi_watchdog_timeout') }
      end

      context 'with watchdog_timeout' do
        let(:params) { { watchdog: true, watchdog_timeout: 30 } }

        it do
          is_expected.to contain_kmod__option('ipmi_watchdog_timeout')
            .with(module: 'ipmi_watchdog', option: 'timeout', value: 30)
            .that_comes_before('Kmod::Load[ipmi_watchdog]')
        end
      end

      context 'with extra watchdog_module_options' do
        let(:params) { { watchdog: true, watchdog_module_options: { 'action' => 'power_cycle' } } }

        it { is_expected.to contain_kmod__option('ipmi_watchdog_action').with(value: 'power_cycle') }
      end

      context 'with a conflicting timeout in watchdog_module_options' do
        let(:params) do
          { watchdog: true, watchdog_timeout: 30, watchdog_module_options: { 'timeout' => 45 } }
        end

        it { is_expected.to compile.and_raise_error(%r{conflicts with ipmi::watchdog_timeout}) }
      end

      context 'with a matching timeout in watchdog_module_options' do
        let(:params) do
          { watchdog: true, watchdog_timeout: 30, watchdog_module_options: { 'timeout' => 30 } }
        end

        it { is_expected.to contain_kmod__option('ipmi_watchdog_timeout').with(value: 30) }
      end

      context 'with timeout only in watchdog_module_options' do
        let(:params) { { watchdog: true, watchdog_module_options: { 'timeout' => 45 } } }

        it { is_expected.to contain_kmod__option('ipmi_watchdog_timeout').with(value: 45) }
      end

      context 'with watchdog_manage_module => false' do
        let(:params) { { watchdog: true, watchdog_manage_module: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('ipmi::watchdog::kmod') }
        it { is_expected.not_to contain_kmod__load('ipmi_watchdog') }
      end

      context 'with watchdog => false and module options set' do
        let(:params) { { watchdog: false, watchdog_timeout: 30 } }

        it { is_expected.not_to contain_kmod__load('ipmi_watchdog') }
      end

      context 'with supervisor auto' do
        context 'and ipmi_systemd_version 252' do
          let(:facts) { super().merge(ipmi_systemd_version: '252') }
          let(:params) { { watchdog: true } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_class('ipmi::watchdog::systemd') }
          it { is_expected.to contain_systemd__system__manage_dropin('50-ipmi-watchdog.conf') }
          it { is_expected.not_to contain_class('ipmi::watchdog::openipmi') }
          it { is_expected.to contain_class('ipmi::watchdog::openipmi::watchdog_param').with(enable: false, only_if_exists: true) }

          it do
            is_expected.to contain_augeas('ipmi_watchdog').with(
              context: "/files#{config_file}",
              changes: ['set IPMI_WATCHDOG no'],
              onlyif: "match /files#{config_file} size > 0",
            )
          end

          it do
            is_expected.to contain_systemd__system__dropin_file('50-ipmi-watchdog.conf').with(
              ensure: 'present',
              content: "# This file is managed with puppet\n#\n[Manager]\nRuntimeWatchdogSec=0\n",
            )
          end

          it { is_expected.to contain_class('ipmi::watchdog::kmod').that_comes_before('Class[ipmi::watchdog::systemd]') }
        end

        context 'and ipmi_systemd_version 1000 (numeric compare)' do
          let(:facts) { super().merge(ipmi_systemd_version: '1000') }
          let(:params) { { watchdog: true } }

          it { is_expected.to contain_class('ipmi::watchdog::systemd') }
        end

        context 'and ipmi_systemd_version 251' do
          let(:facts) { super().merge(ipmi_systemd_version: '251') }
          let(:params) { { watchdog: true } }

          it { is_expected.not_to contain_class('ipmi::watchdog::systemd') }
          it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG yes']) }
        end

        context 'and no ipmi_systemd_version fact' do
          let(:params) { { watchdog: true } }

          it { is_expected.not_to contain_class('ipmi::watchdog::systemd') }
        end

        context "and only puppet/systemd's systemd_version fact" do
          let(:facts) { super().merge(systemd_version: '257') }
          let(:params) { { watchdog: true } }

          it { is_expected.not_to contain_class('ipmi::watchdog::systemd') }
        end

        context 'and watchdog => false removes the drop-in' do
          let(:facts) { super().merge(ipmi_systemd_version: '257') }

          it { is_expected.to contain_systemd__system__dropin_file('50-ipmi-watchdog.conf').with(ensure: 'absent') }
          it { is_expected.not_to contain_class('ipmi::watchdog::kmod') }
        end
      end

      context 'with supervisor systemd on an old systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '219') }
        let(:params) { { watchdog: true, watchdog_supervisor: 'systemd' } }

        it { is_expected.to contain_class('ipmi::watchdog::systemd') }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG no']) }
      end

      context 'with supervisor openipmi on a new systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_supervisor: 'openipmi' } }

        it { is_expected.not_to contain_class('ipmi::watchdog::systemd') }
        it { is_expected.to contain_augeas('ipmi_watchdog').with(changes: ['set IPMI_WATCHDOG yes']) }
      end

      context 'with watchdog_timeout under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_timeout: 30 } }

        it { is_expected.to contain_kmod__option('ipmi_watchdog_timeout').with(value: 30) }

        it do
          is_expected.to contain_systemd__system__dropin_file('50-ipmi-watchdog.conf')
            .with_content(%r{^RuntimeWatchdogSec=30$})
        end
      end

      context 'with watchdog_systemd_options forcing RuntimeWatchdogSec off' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) do
          {
            watchdog: true,
            watchdog_timeout: 30,
            watchdog_systemd_options: { 'RuntimeWatchdogSec' => '0' },
          }
        end

        it { is_expected.to contain_kmod__load('ipmi_watchdog') }

        it do
          is_expected.to contain_systemd__system__dropin_file('50-ipmi-watchdog.conf')
            .with_content(%r{^RuntimeWatchdogSec=0$})
        end
      end

      context 'with watchdog_systemd_options overriding the timeout' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) do
          {
            watchdog: true,
            watchdog_timeout: 30,
            watchdog_systemd_options: { 'RuntimeWatchdogSec' => '45', 'WatchdogDevice' => '/dev/watchdog0' },
          }
        end

        it do
          is_expected.to contain_systemd__system__dropin_file('50-ipmi-watchdog.conf')
            .with_content(%r{^RuntimeWatchdogSec=45$})
            .with_content(%r{^WatchdogDevice=/dev/watchdog0$})
        end
      end

      context 'with watchdog_manage_module => false under systemd' do
        let(:facts) { super().merge(ipmi_systemd_version: '257') }
        let(:params) { { watchdog: true, watchdog_manage_module: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('ipmi::watchdog::systemd') }
        it { is_expected.not_to contain_kmod__load('ipmi_watchdog') }
      end
    end
  end
end
