require 'spec_helper'

describe 'ipmi::network' :class do

  let(:title) {'example'}
  let(:facts) { { :operatingsystem           => 'RedHat',
                  :osfamily                  => 'redhat',
                  :operatingsystemmajrelease => '7', } }


  describe 'when deploying as dhcp with all params' do
    let(:params) do {
      :ip => 1.1.1.1,
      :netmask => 255.255.255.0,
      :gateway => 2.2.2.2,
      :type => 'dhcp',
      :lan_channel => 1,
      :interface_type => 'dedicated',
    }

    it { is_expected.to contain_exec('ipmi_set_dhcp_1') }
    it { is_expected.to contain_exec('ipmi_set_interface_type_1') }

  end

end
