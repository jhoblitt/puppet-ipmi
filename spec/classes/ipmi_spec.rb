require 'spec_helper'

describe 'ipmi', :type => :class do

  describe 'for osfamily RedHat' do
    let :facts do
      {
        :osfamily          => 'RedHat',
        :lsbmajdistrelease => '6',
      }
    end

    describe 'no params' do
      it { should include_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::service').with_start_ipmievd(false) }
    end

    describe 'with start_ipmievd => false' do
      let(:params) {{ :start_ipmievd => false }}

      it { should include_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::service').with_start_ipmievd(false) }
    end

    describe 'with start_ipmievd => true' do
      let(:params) {{ :start_ipmievd => true }}

      it { should include_class('ipmi') }
      it { should contain_class('ipmi::params') }
      it { should contain_class('ipmi::install') }
      it { should contain_class('ipmi::service').with_start_ipmievd(true) }
    end

    describe 'with start_ipmievd => not-a-bool' do
      let(:params) {{ :start_ipmievd => 'not-a-bool' }}

      it 'should fail' do
        expect {
          should include_class('ipmi')
        }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end

end
