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
    end
  end
end
