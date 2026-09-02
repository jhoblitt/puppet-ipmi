# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::network', type: :define do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts.merge(
          {
            ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
            ipmi: { default: { channel: 1 } }
          }
        )
      end
      let(:title) { 'example' }

      describe 'when deploying as dhcp with minimal params' do
        let(:params) do
          {
            type: 'dhcp',
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_network('ipmi_network_example').with(
            lan_channel: 1,
            type: 'dhcp'
          )
        }
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

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_network('ipmi_network_example').with(
            lan_channel: 1,
            type: 'dhcp'
          )
        }
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

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_network('ipmi_network_example').with(
            lan_channel: 1,
            type: 'static',
            ip: '1.1.1.10',
            netmask: '255.255.255.0',
            gateway: '1.1.1.1'
          )
        }
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

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_ipmi_network('ipmi_network_example').with(
            lan_channel: 2,
            type: 'static',
            ip: '1.1.1.10',
            netmask: '255.255.255.0',
            gateway: '1.1.1.1'
          )
        }
      end
    end
  end
end
