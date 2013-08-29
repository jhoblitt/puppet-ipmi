require 'spec_helper'

describe 'ipmi', :type => :class do

  describe 'for osfamily RedHat' do
    let :facts do
      {
        :osfamily          => 'RedHat',
        :lsbmajdistrelease => '6',
      }
    end

    describe 'el6.x' do
      before { facts[:lsbmajdistrelease] = '6' }
  
      it { should include_class('ipmi') }
      it { should include_class('ipmi::params') }
      it { should include_class('ipmi::install') }
      it { should include_class('ipmi::service') }
    end
  end

end
