# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::user', type: :define do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) do
        facts.merge(
          {
            ipmitool_mc_info: { IPMI_Puppet_Service_Recommend: 'running' },
            ipmitool: { mc_info: { 'Manufacturer Name' => 'Generic' } },
            ipmi: { default: { channel: 1 } }
          }
        )
      end
      let(:title) { 'newuser' }

      context 'when deploying with password param' do
        let(:params) do
          {
            password: 'password',
          }
        end

        it { is_expected.to contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true') }

        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true') }
        it { is_expected.to contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }

        it { is_expected.not_to contain_exec('ipmi_user_disable_newuser') }
        it { is_expected.not_to contain_exec('ipmi_user_disable_sol_newuser') }
      end

      context 'when deploying with all params' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            priv: 3,
            user_id: 4,
          }
        end

        it { is_expected.to contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true') }

        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true') }
        it { is_expected.to contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }
      end

      context 'when deploying with all params and a sensitive password' do
        let(:params) do
          {
            user: 'newuser1',
            password: sensitive('password'),
            priv: 3,
            user_id: 4,
          }
        end

        it { is_expected.to contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true') }

        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true') }
        it { is_expected.to contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }
      end

      describe 'when deploying with no params' do
        it 'fails and raise password required error' do
          expect { is_expected.to contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, %r{You must supply a password to enable})
        end
      end

      describe 'when deploying with invalid priv' do
        let(:params) do
          {
            user: 'newuser1',
            password: 'password',
            priv: 5,
            user_id: 4,
          }
        end

        it 'fails and raise invalid privilege error' do
          expect { is_expected.to contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, %r{invalid privilege level specified})
        end
      end

      describe 'when deploying without a password set' do
        let(:params) do
          {
            enable: true
          }
        end

        it 'fails and raise password required error' do
          expect { is_expected.to contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, %r{You must supply a password to enable})
        end
      end

      describe 'when disabling a user' do
        let(:params) do
          {
            enable: false
          }
        end

        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_disable_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_disable_sol_newuser]') }
        it { is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

        it { is_expected.to contain_exec('ipmi_user_disable_newuser').with('refreshonly' => 'true') }
        it { is_expected.to contain_exec('ipmi_user_disable_sol_newuser').with('refreshonly' => 'true') }
        it { is_expected.to contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }

        it { is_expected.not_to contain_exec('ipmi_user_enable_newuser') }
        it { is_expected.not_to contain_exec('ipmi_user_enable_sol_newuser') }

      end
    end
  end
  
  # Test Dell-specific functionality separately
  describe 'ipmi::user Dell functionality', type: :define do
    let(:title) { 'newuser' }
    let(:params) { { enable: false } }
    
    context 'with Dell hardware' do
      let(:facts) do
        {
          ipmitool_mc_info: { IPMI_Puppet_Service_Recommend: 'running' },
          ipmitool: { 
            mc_info: { 
              'Manufacturer Name' => 'Dell Inc.'
            }
          },
          ipmi: { default: { channel: 1, users: { '3' => { 'name' => 'newuser' }}}}
        }
      end
      
      it { is_expected.to contain_exec('ipmi_dell_clear_username_newuser').with(
        'command' => '/usr/bin/ipmitool user set name 3 \'\'',
        'onlyif' => "/bin/test -n 'newuser'",
        'subscribe' => 'Exec[ipmi_user_priv_newuser]'
      )}
    end
    
    context 'with non-Dell hardware' do
      let(:facts) do
        {
          ipmitool_mc_info: { IPMI_Puppet_Service_Recommend: 'running' },
          ipmitool: { 
            mc_info: { 
              'Manufacturer Name' => 'SuperMicro'
            }
          },
          ipmi: { default: { channel: 1 }}
        }
      end
      
      it { is_expected.not_to contain_exec('ipmi_dell_clear_username_newuser') }
    end
  end
end
