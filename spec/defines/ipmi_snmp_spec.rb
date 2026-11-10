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
        },

      },
      ipmitool: { mc_info: { IPMI_Puppet_Service_Recommend: 'running' } },
      ipmi: { default: { channel: 1 } },
    }
  end

  let(:title) { 'example' }

  describe 'when deploying with no params' do
    it { is_expected.to contain_exec('ipmi_set_snmp_1') }
  end

  describe 'when deploying with all params' do
    let(:params) do
      {
        snmp: 'secret',
        lan_channel: 2,
      }
    end

    it { is_expected.to contain_exec('ipmi_set_snmp_2') }
  end

  describe 'when deployed via create_resources' do
    let(:title) { 'snmp1' }
    let(:params) do
      {
        snmp: 'secret',
        lan_channel: 1,
      }
    end

    it { is_expected.to contain_exec('ipmi_set_snmp_1').with(command: '/usr/bin/ipmitool lan set 1 snmp secret') }
  end
end
