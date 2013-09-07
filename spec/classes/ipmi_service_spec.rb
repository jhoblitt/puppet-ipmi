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
      :ensure => 'running',
      :hasstatus => 'true',
      :hasrestart => 'true',
      :enable => 'true',
    })
  end

end
