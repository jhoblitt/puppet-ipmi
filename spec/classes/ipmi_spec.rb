require 'spec_helper'

describe 'ipmi', :type => :class do

  describe 'for osfamily RedHat' do
    let :facts do
      {
        :osfamily                  => 'RedHat',
        :operatingsystemmajrelease => '6',
      }
    end

    describe 'no params' do
      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
        should contain_service('ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => running' do
      let(:params) {{ :service_ensure => 'running' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => stopped' do
      let(:params) {{ :service_ensure => 'stopped' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => invalid-string' do
      let(:params) {{ :service_ensure => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /does not match/)
      end
    end

    describe 'ipmievd_service_ensure => running' do
      let(:params) {{ :ipmievd_service_ensure => 'running' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'running',
          :enable => true,
        })
      end
    end

    describe 'ipmievd_service_ensure => stopped' do
      let(:params) {{ :ipmievd_service_ensure => 'stopped' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'ipmievd_service_ensure => invalid-string' do
      let(:params) {{ :ipmievd_service_ensure => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /does not match/)
      end
    end

    describe 'watchdog => true' do
      let(:params) {{ :watchdog => true }}

      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG yes',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'watchdog => false' do
      let(:params) {{ :watchdog => false }}

      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/sysconfig/ipmi').with({
          'context' => '/files/etc/sysconfig/ipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'watchdog => invalid-string' do
      let(:params) {{ :watchdog => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end

  end

  describe 'for osfamily Debian' do
    let :facts do
      {
        :osfamily                  => 'Debian',
        :operatingsystem           => 'Ubuntu',
      }
    end

    describe 'no params' do
      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
        should contain_service('openipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => running' do
      let(:params) {{ :service_ensure => 'running' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => stopped' do
      let(:params) {{ :service_ensure => 'stopped' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'service_ensure => invalid-string' do
      let(:params) {{ :service_ensure => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /does not match/)
      end
    end

    describe 'ipmievd_service_ensure => running' do
      let(:params) {{ :ipmievd_service_ensure => 'running' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'running',
          :enable => true,
        })
      end
    end

    describe 'ipmievd_service_ensure => stopped' do
      let(:params) {{ :ipmievd_service_ensure => 'stopped' }}

      it { should create_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'ipmievd_service_ensure => invalid-string' do
      let(:params) {{ :ipmievd_service_ensure => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /does not match/)
      end
    end

    describe 'watchdog => true' do
      let(:params) {{ :watchdog => true }}

      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG yes',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'watchdog => false' do
      let(:params) {{ :watchdog => false }}

      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::config') }
      it do
        should contain_augeas('/etc/default/openipmi').with({
          'context' => '/files/etc/default/openipmi',
          'changes' => [
            'set IPMI_WATCHDOG no',
          ],
        })
      end
      it do
        should contain_class('ipmi::service::ipmi').with({
          :ensure => 'running',
          :enable => true,
        })
      end
      it do
        should contain_class('ipmi::service::ipmievd').with({
          :ensure => 'stopped',
          :enable => false,
        })
      end
    end

    describe 'watchdog => invalid-string' do
      let(:params) {{ :watchdog => 'invalid-string' }}

      it 'should fail' do
        expect {
          should contain_class('ipmi')
        }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end

  end

end
