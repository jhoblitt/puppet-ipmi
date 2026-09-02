# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::snmp', type: :define do
  let(:facts) do
    {
      os: {
        family: 'RedHat',
        name: 'CentOS',
        release: {
          major: 9,
        }

      },
      ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
      ipmi: { default: { channel: 1 } },
    }
  end

  let(:title) { 'example' }

  describe 'when deploying with no params' do
    it { is_expected.to compile.with_all_deps }

    it {
      is_expected.to contain_ipmi_snmp('ipmi_snmp_example').with(
        lan_channel: 1,
        community: 'public'
      )
    }
  end

  describe 'when deploying with all params' do
    let(:params) do
      {
        snmp: 'secret',
        lan_channel: 2,
      }
    end

    it { is_expected.to compile.with_all_deps }

    it {
      is_expected.to contain_ipmi_snmp('ipmi_snmp_example').with(
        lan_channel: 2,
        community: 'secret'
      )
    }
  end
end
