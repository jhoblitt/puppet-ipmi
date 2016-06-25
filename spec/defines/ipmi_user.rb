require 'spec_helper'

describe 'ipmi::user' :class do

  let(:title) {'newuser'}
  let(:facts) { { :operatingsystem           => 'RedHat',
                  :osfamily                  => 'redhat',
                  :operatingsystemmajrelease => '7', } }


  describe 'when deploying with all params' do
    let(:params) do {
      :user => 'newuser1',
      :password => 'password',
      :priv     => 4,
      :user_id => 3,
    }

    it {
      is_expected.to contain_exec('ipmi_user_enable_newuser').with('refreshonly' => 'true')

      is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_priv_newuser]')
      is_expected.to contain_exec('ipmi_user_add_newuser').that_notifies('Exec[ipmi_user_setpw_newuser]')

      is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_newuser]')
      is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]')
      is_expected.to contain_exec('ipmi_user_priv_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]')

      is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_newuser]')
      is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_enable_sol_newuser]')
      is_expected.to contain_exec('ipmi_user_setpw_newuser').that_notifies('Exec[ipmi_user_channel_setaccess_newuser]')

      is_expected.to contain_exec('ipmi_user_enable_sol_newuser').with('refreshonly' => 'true')
      is_expected.to contain_exec('ipmi_user_channel_setaccess_newuser').with('refreshonly' => 'true')
    }

  end

end
