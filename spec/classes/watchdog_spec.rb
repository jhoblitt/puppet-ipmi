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
      end
    end
  end
end
