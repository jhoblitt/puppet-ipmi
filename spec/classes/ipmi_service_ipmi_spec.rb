require 'spec_helper'

describe 'ipmi::service::ipmi', :type => :class do

  describe 'no params' do
    it { should include_class('ipmi::service::ipmi') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => true,
        :hasrestart => true,
        :enable     => true,
      })
    end
  end

  describe 'with enable => false' do
    let(:params) {{ :enable => false }}

    it { should include_class('ipmi::service::ipmi') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => true,
        :hasrestart => true,
        :enable     => false,
      })
    end
  end

  describe 'with enable => true' do
    let(:params) {{ :enable => true }}

    it { should include_class('ipmi::service::ipmi') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => true,
        :hasrestart => true,
        :enable     => true,
      })
    end
  end

  describe 'with enable => not-a-bool' do
    let(:params) {{ :enable => 'not-a-bool' }}

    it 'should fail' do
      expect {
        should include_class('ipmi::service')
      }.to raise_error(Puppet::Error, /is not a boolean/)
    end
  end

  describe 'with ensure => running' do
    let(:params) {{ :ensure => 'running' }}

    it { should include_class('ipmi::service::ipmi') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => true,
        :hasrestart => true,
        :enable     => true,
      })
    end
  end

  describe 'with ensure => running' do
    let(:params) {{ :ensure => 'stopped' }}

    it { should include_class('ipmi::service::ipmi') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'stopped',
        :hasstatus  => true,
        :hasrestart => true,
        :enable     => true,
      })
    end
  end


  describe 'with ensure => invalid-string' do
    let(:params) {{ :ensure => 'invalid-string' }}

    it 'should fail' do
      expect {
        should include_class('ipmi::service::ipmi')
      }.to raise_error(Puppet::Error, /does not match/)
    end
  end

end
