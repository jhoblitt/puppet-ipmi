require 'spec_helper'

describe 'ipmi::snmp' :class do

  let(:title) {'example'}
  let(:facts) { { :operatingsystem           => 'RedHat',
                  :osfamily                  => 'redhat',
                  :operatingsystemmajrelease => '7', } }


  describe 'when deploying with all params' do
    let(:params) do {
      :snmp        => 'public',
      :lan_channel => 1,
    }

    it { is_expected.to contain_exec('ipmi_set_snmp_1') }

  end

end
