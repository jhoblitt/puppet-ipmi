require 'spec_helper'

describe 'ipmi::service', :type => :class do

  describe 'no params' do
    it { should include_class('ipmi::service') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'true',
      })
    end
    it do
      should contain_service('ipmievd').with({
        :ensure     => 'stopped',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'false',
      })
    end
  end

  describe 'with start_ipmievd => false' do
    let(:params) {{ :start_ipmievd => false }}

    it { should include_class('ipmi::service') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'true',
      })
    end
    it do
      should contain_service('ipmievd').with({
        :ensure     => 'stopped',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'false',
      })
    end
  end

  describe 'with start_ipmievd => true' do
    let(:params) {{ :start_ipmievd => true }}

    it { should include_class('ipmi::service') }
    it do
      should contain_service('ipmi').with({
        :ensure     => 'running',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'true',
      })
    end
    it do
      should contain_service('ipmievd').with({
        :ensure     => 'running',
        :hasstatus  => 'true',
        :hasrestart => 'true',
        :enable     => 'true',
      })
    end
  end

  describe 'with start_ipmievd => not-a-bool' do
    let(:params) {{ :start_ipmievd => 'not-a-bool' }}

    describe 'with start_ipmievd => not-a-bool' do
      let(:params) {{ :start_ipmievd => 'not-a-bool' }}

      it 'should fail' do
        expect {
          should include_class('ipmi::service')
        }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end

end
