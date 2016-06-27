require 'spec_helper'

describe 'ipmi::user', :type => :define do
  let(:facts) {{
    :operatingsystem           => 'RedHat',
    :osfamily                  => 'redhat',
    :operatingsystemmajrelease => '7',
  }}

  let(:title) { 'newuser' }

  describe 'when deploying with all params' do
    let(:params) {{
      :password => 'password',
    }}

    it { should contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true') }

    it { should contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]') }
    it { should contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]') }

    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

    it { should contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true') }
    it { should contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }
  end

  describe 'when deploying with all params' do
    let(:params) {{
      :user     => 'newuser1',
      :password => 'password',
      :priv     => 3,
      :user_id  => 4,
    }}

    it { should contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true') }

    it { should contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]') }
    it { should contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]') }

    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
    it { should contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]') }
    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]') }
    it { should contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]') }

    it { should contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true') }
    it { should contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true') }
  end

  describe 'when deploying with no params' do
    it 'should fail and raise password required error' do
      expect { should contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, /password/)
    end
  end

  describe 'when deploying with invalid priv' do
    let(:params) {{
      :user     => 'newuser1',
      :password => 'password',
      :priv     => 5,
      :user_id  => 4,
    }}

    it 'should fail and raise invalid privilege error' do
      expect { should contain_exec('ipmi_user_enable_newuser') }.to raise_error(Puppet::Error, /invalid privilege level specified/)
    end
  end
end
