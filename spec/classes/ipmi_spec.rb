require 'spec_helper'

describe 'ipmi', :type => 'class' do

  describe 'for osfamily RedHat' do
    it { should contain_class('ipmi') }
  end

end
