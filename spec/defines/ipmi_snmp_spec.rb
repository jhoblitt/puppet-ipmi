require 'spec_helper'

describe 'ipmi::snmp', :type => :define do
  let(:facts) {{
    :operatingsystem           => 'RedHat',
    :osfamily                  => 'redhat',
    :operatingsystemmajrelease => '7',
  }}

  let(:title) { 'example' }

  describe 'when deploying with no params' do
    it { should contain_exec('ipmi_set_snmp_1') }
  end

  describe 'when deploying with all params' do
    let(:params) {{
      :snmp        => 'secret',
      :lan_channel => 2,
    }}

    it { should contain_exec('ipmi_set_snmp_2') }
  end

  describe 'when deploying with invalid type' do
    let(:params) {{
      :snmp        => 'secret',
      :lan_channel => 'a',
    }}

    it 'should fail with invalid integer' do
      expect { should contain_exec('ipmi_set_snmp_a') }.to raise_error(Puppet::Error, /Expected first argument to be an Integer/)
    end
  end
end
