require 'spec_helper'

describe 'ipmi::params', :type => :class do
  describe 'for osfamily RedHat' do
    let(:facts) {{ :osfamily => 'RedHat' }}

    describe 'el5.x' do
      before { facts[:operatingsystemmajrelease] = '5' }

     it { should create_class('ipmi::params') }
    end

    describe 'el6.x' do
      before { facts[:operatingsystemmajrelease] = '6' }

     it { should create_class('ipmi::params') }
    end

    describe 'el7.x' do
      before { facts[:operatingsystemmajrelease] = '7' }

     it { should create_class('ipmi::params') }
    end

    describe 'el8.x' do
      before { facts[:operatingsystemmajrelease] = '8' }

     it { should create_class('ipmi::params') }
    end

    describe 'unsupported operatingsystemmajrelease' do
      before { facts[:operatingsystemmajrelease] = '1' }

      it 'should fail' do
        expect { should create_class('ipmi::params') }.
          to raise_error(Puppet::Error, /not supported on operatingsystemmajrelease 1/)
      end
    end
  end

  describe 'for osfamily Debian' do
    let(:facts) {{ :osfamily => 'Debian' }}

    describe 'Debian' do
      before { facts[:operatingsystem] = 'Debian' }

     it { should create_class('ipmi::params') }
    end

    describe 'Ubuntu' do
      before { facts[:operatingsystem] = 'Ubuntu' }

     it { should create_class('ipmi::params') }
    end

    describe 'unsupported Debian based operatingsystem' do
      before { facts[:operatingsystem] = 'LinuxMint' }

      it 'should fail' do
        expect { should contain_class('ipmi::params') }.
          to raise_error(Puppet::Error, /Module ipmi is not supported on operatingsystem LinuxMint/)
      end
    end
  end

  describe 'unsupported osfamily' do
    let :facts do
    {
      :osfamily        => 'Solaris',
      :operatingsystem => 'Nexenta',
    }
    end

    it 'should fail' do
      expect { should contain_class('ipmi::params') }.
        to raise_error(Puppet::Error, /not supported on Nexenta/)
    end
  end

end
