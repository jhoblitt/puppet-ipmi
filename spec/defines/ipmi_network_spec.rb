require 'spec_helper'

describe 'ipmi::network', :type => :define do
  let(:facts) {{
    :operatingsystem           => 'RedHat',
    :osfamily                  => 'redhat',
    :operatingsystemmajrelease => '7',
  }}

  let(:title) { 'example' }

  describe 'when deploying as dhcp with minimal params' do
    let(:params) {{
      :type => 'dhcp',
    }}

    it { should contain_exec('ipmi_set_dhcp_1') }
  end

  describe 'when deploying as dhcp with all params' do
    let(:params) {{
      :ip             => '1.1.1.1',
      :netmask        => '255.255.255.0',
      :gateway        => '2.2.2.2',
      :type           => 'dhcp',
      :lan_channel    => 1,
    }}

    it { should contain_exec('ipmi_set_dhcp_1') }
  end

  describe 'when deploying as static with minimal params' do
    let(:params) {{
      :ip             => '1.1.1.10',
      :netmask        => '255.255.255.0',
      :gateway        => '1.1.1.1',
      :type           => 'static',
    }}

    it { should contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_ipaddr_1]') }
    it { should contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_defgw_1]') }
    it { should contain_exec('ipmi_set_static_1').that_notifies('Exec[ipmi_set_netmask_1]') }
  end

  describe 'when deploying as static with all params' do
    let(:params) {{
      :ip             => '1.1.1.10',
      :netmask        => '255.255.255.0',
      :gateway        => '1.1.1.1',
      :type           => 'static',
      :lan_channel    => 2,
    }}

    it { should contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_ipaddr_2]') }
    it { should contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_defgw_2]') }
    it { should contain_exec('ipmi_set_static_2').that_notifies('Exec[ipmi_set_netmask_2]') }
  end

  describe 'when deploying with incorrect lan_channel' do
    let(:params) {{
      :ip             => '1.1.1.1',
      :netmask        => '255.255.255.0',
      :gateway        => '2.2.2.2',
      :type           => 'dhcp',
      :lan_channel    => 'a',
    }}

    it 'should fail with invalid integer' do
      expect { should contain_exec('ipmi_set_dhcp_1') }.to raise_error(Puppet::Error, /Expected first argument to be an Integer/)
    end
  end

  describe 'when deploying with invalid type' do
    let(:params) {{
      :ip             => '1.1.1.1',
      :netmask        => '255.255.255.0',
      :gateway        => '2.2.2.2',
      :type           => 'invalid',
      :lan_channel    => 1,
    }}

    it 'should fail with invalid type' do
      expect { should contain_exec('ipmi_set_invalid_1') }.to raise_error(Puppet::Error, /Network type must be either dhcp or static/)
    end
  end
end
