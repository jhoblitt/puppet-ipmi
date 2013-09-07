require 'spec_helper'

describe 'ipmi::service', :type => :class do

  it do
    should contain_service('ipmi').with({
      :ensure => 'running',
      :hasstatus => 'true',
      :hasrestart => 'true',
      :enable => 'true',
    })
  end

  it do
    should contain_service('ipmievd').with({
      :ensure => 'stopped',
      :hasstatus => 'true',
      :hasrestart => 'true',
      :enable => 'false',
    })
  end

  describe 'with start_ipmievd => true' do
    let :params do
      {
        :start_ipmievd => 'true',
      }
    end
    it do
      should contain_service('ipmievd').with({
        :ensure => 'running',
        :hasstatus => 'true',
        :hasrestart => 'true',
        :enable => 'true',
      })
    end
  end
end
