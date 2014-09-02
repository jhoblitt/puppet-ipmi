require 'spec_helper'

describe 'ipmi::params', :type => :class do
  describe 'for osfamily RedHat' do
    let(:facts) {{ :osfamily => 'RedHat' }}

    describe 'el5.x' do
      before { facts[:operatingsystemmajrelease] = '5' }

      it { should include_class('ipmi::params') }
    end

    describe 'el6.x' do
      before { facts[:operatingsystemmajrelease] = '6' }
  
      it { should include_class('ipmi::params') }
    end

    describe 'el7.x' do
      before { facts[:operatingsystemmajrelease] = '7' }

      it { should include_class('ipmi::params') }
    end

    describe 'unsupported operatingsystemmajrelease' do
      before { facts[:operatingsystemmajrelease] = '1' }

      it 'should fail' do
        expect { should include_class('ipmi::params') }.
          to raise_error(Puppet::Error, /not supported on operatingsystemmajrelease 1/)
      end
    end
  end

  describe 'unsupported osfamily' do
    let :facts do 
      {
        :osfamily        => 'Debian',
        :operatingsystem => 'Debian',
      }
    end
  
    it 'should fail' do
      expect { should include_class('ipmi::params') }.
        to raise_error(Puppet::Error, /not supported on Debian/)
    end
  end

end
