# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi'

describe PuppetX::Ipmi do
  describe '.unwrap' do
    it 'returns the value a Sensitive wraps' do
      expect(described_class.unwrap(Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret'))).to eq('secret')
    end

    it 'returns any other value unchanged' do
      expect(described_class.unwrap('secret')).to eq('secret')
      expect(described_class.unwrap(nil)).to be_nil
    end
  end
end
