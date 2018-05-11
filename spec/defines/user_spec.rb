# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::user' do
  let(:title) { 'foobar' }

  let(:params) do
    {
      password: 'foobar',
    }
  end
  # Puppet::Util::Log.level = :debug
  # Puppet::Util::Log.newdestination(:console)
  let(:pre_condition) { 'include ipmi' }

  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts }

      describe 'check default config' do
        it { is_expected.to compile.with_all_deps }
        it do
          is_expected.to contain_exec('ipmi_user_enable_foobar').with(
            command: '/usr/bin/ipmitool user enable 3',
            refreshonly: true,
          )
        end
        it do
          is_expected.to contain_exec('ipmi_user_add_foobar').with(
            command: '/usr/bin/ipmitool user set name 3 foobar',
            unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^3' | awk '{print $2}')\" = \"foobar\"",
            notify: ['Exec[ipmi_user_priv_foobar]', 'Exec[ipmi_user_setpw_foobar]'],
          )
        end
        it do
          is_expected.to contain_exec('ipmi_user_priv_foobar').with(
            command: '/usr/bin/ipmitool user priv 3 4 1',
            unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^3' | awk '{print $6}')\" = ADMINISTRATOR",
            notify: ['Exec[ipmi_user_enable_foobar]', 'Exec[ipmi_user_enable_sol_foobar]', 'Exec[ipmi_user_channel_setaccess_foobar]'],
          )
        end
        it do
          is_expected.to contain_exec('ipmi_user_setpw_foobar').with(
            command: '/usr/bin/ipmitool user set password 3 \'foobar\'',
            unless: "/usr/bin/ipmitool user test 3 16 'foobar'",
            notify: ['Exec[ipmi_user_enable_foobar]', 'Exec[ipmi_user_enable_sol_foobar]', 'Exec[ipmi_user_channel_setaccess_foobar]'],
          )
        end
        it do
          is_expected.to contain_exec('ipmi_user_enable_sol_foobar').with(
            command: '/usr/bin/ipmitool sol payload enable 1 3',
            refreshonly: true,
          )
        end
        it do
          is_expected.to contain_exec('ipmi_user_channel_setaccess_foobar').with(
            command: '/usr/bin/ipmitool channel setaccess 1 3 callin=on ipmi=on link=on privilege=4',
            refreshonly: true,
          )
        end
      end
      describe 'Change Defaults' do
        context 'password' do
          before(:each) { params.merge!(password: 'password') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_user_setpw_foobar').with(
              command: '/usr/bin/ipmitool user set password 3 \'password\'',
              unless: "/usr/bin/ipmitool user test 3 16 'password'",
            )
          end
        end
        context 'user' do
          before(:each) { params.merge!(user: 'root') }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_user_add_foobar').with(
              command: '/usr/bin/ipmitool user set name 3 root',
              unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^3' | awk '{print $2}')\" = \"root\"",
            )
          end
        end
        context 'priv' do
          before(:each) { params.merge!(priv: 1) }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_user_priv_foobar').with(
              command: '/usr/bin/ipmitool user priv 3 1 1',
              unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^3' | awk '{print $6}')\" = CALLBACK",
            )
          end
        end
        context 'user_id' do
          before(:each) { params.merge!(user_id: 42) }
          it { is_expected.to compile }
          it do
            is_expected.to contain_exec('ipmi_user_enable_foobar').with(
              command: '/usr/bin/ipmitool user enable 42',
              refreshonly: true,
            )
          end
          it do
            is_expected.to contain_exec('ipmi_user_add_foobar').with(
              command: '/usr/bin/ipmitool user set name 42 foobar',
              unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^42' | awk '{print $2}')\" = \"foobar\"",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_user_priv_foobar').with(
              command: '/usr/bin/ipmitool user priv 42 4 1',
              unless: "/usr/bin/test \"$(ipmitool user list 1 | grep '^42' | awk '{print $6}')\" = ADMINISTRATOR",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_user_setpw_foobar').with(
              command: '/usr/bin/ipmitool user set password 42 \'foobar\'',
              unless: "/usr/bin/ipmitool user test 42 16 'foobar'",
            )
          end
          it do
            is_expected.to contain_exec('ipmi_user_enable_sol_foobar').with(
              command: '/usr/bin/ipmitool sol payload enable 1 42',
              refreshonly: true,
            )
          end
          it do
            is_expected.to contain_exec('ipmi_user_channel_setaccess_foobar').with(
              command: '/usr/bin/ipmitool channel setaccess 1 42 callin=on ipmi=on link=on privilege=4',
              refreshonly: true,
            )
          end
        end
      end
      describe 'check bad type' do
        context 'password' do
          before(:each) { params.merge!(password: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'user' do
          before(:each) { params.merge!(user: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'priv' do
          before(:each) { params.merge!(priv: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
        context 'user_id' do
          before(:each) { params.merge!(user_id: true) }
          it { is_expected.to raise_error(Puppet::Error) }
        end
      end
    end
  end
end
