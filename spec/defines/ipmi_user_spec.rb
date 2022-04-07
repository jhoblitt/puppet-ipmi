# frozen_string_literal: true

require 'spec_helper'

describe 'ipmi::user', type: :define do
  let(:facts) do
    {
      operatingsystem: 'RedHat',
      osfamily: 'redhat',
      operatingsystemmajrelease: '7',
    }
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

  describe 'when deploying with no params' do
    it 'fails and raise password required error' do
      expect { is_expected.to contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, %r{password})
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
end
