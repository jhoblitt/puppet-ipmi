# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::snmp_community' do
  let(:title) { 'public' }
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
          is_expected.to contain_exec('ipmi_set_snmp_1').with(
            command: '/usr/bin/ipmitool lan set 1 snmp public',
            onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"public\"",
          )
        end
      end
      describe 'Change Defaults' do
        context 'community' do
          before(:each) { params.merge!(community: 'private') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_snmp_1').with(
              command: '/usr/bin/ipmitool lan set 1 snmp private',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 1 | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"private\"",
            )
          end
        end
        context 'lan_channel' do
          before(:each) { params.merge!(lan_channel: 42) }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_set_snmp_42').with(
              command: '/usr/bin/ipmitool lan set 42 snmp public',
              onlyif: "/usr/bin/test \"$(ipmitool lan print 42 | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"public\"",
            )
          end
        end
      end
      describe 'check bad type' do
        context 'snmp' do
          before(:each) { params.merge!(snmp: true) }
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
