# frozen_string_literal: true

require 'spec_helper'

describe 'wrapper', type: :class do
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

      let(:pre_condition) do
        <<-PP
          class wrapper (
            String $service_ensure = 'running',
            Stdlib::Ensure::Service $ipmievd_service_ensure = 'stopped',
          ) {
            class { 'ipmi':
              service_ensure         => $service_ensure,
              ipmievd_service_ensure => $ipmievd_service_ensure,
            }
            contain ipmi::service
          }
        PP
      end

      case facts[:os]['family']
      when 'RedHat'
        let(:service_name) { 'ipmi' }
      when 'Debian'
        let(:service_name) { 'openipmi' }
      end

      it { is_expected.to compile.with_all_deps }
      it { is_expected.to contain_class('ipmi::service') }
      it { is_expected.to contain_class('ipmi::service::ipmi') }
      it { is_expected.to contain_class('ipmi::service::ipmievd') }

      context 'with default params' do
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

        it do
          is_expected.to contain_service(service_name).with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end

      context 'with ipmievd_service_ensure => running' do
        let(:params) { { ipmievd_service_ensure: 'running' } }

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'running',
            enable: true,
          )
        end
      end

      context 'with ipmievd_service_ensure => stopped' do
        let(:params) { { ipmievd_service_ensure: 'stopped' } }

        it do
          is_expected.to contain_service('ipmievd').with(
            ensure: 'stopped',
            enable: false,
          )
        end
      end
    end
  end
end
