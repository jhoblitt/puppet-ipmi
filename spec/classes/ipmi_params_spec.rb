require 'spec_helper'

describe 'ipmi::params', :type => :class do
  describe 'for osfamily RedHat' do
    let :facts do
      {
        :osfamily => 'RedHat',
      }
    end

    describe 'el5.x' do
      before { facts[:lsbmajdistrelease] = '5' }

      it { should include_class('ipmi::params') }
    end

    describe 'el6.x' do
      before { facts[:lsbmajdistrelease] = '6' }
  
      it { should include_class('ipmi::params') }
    end

    describe 'unsupported lsbmajdistrelease' do
      before { facts[:lsbmajdistrelease] = '7' }

      it 'should fail' do
        expect { should include_class('ipmi::params') }.
          to raise_error(Puppet::Error, /not supported on lsbmajdistrelease 7/)
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
