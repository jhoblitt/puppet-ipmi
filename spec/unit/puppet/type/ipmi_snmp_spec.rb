# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp) do
  describe 'when validating attributes' do
    %i[name lan_channel ipmitool_cmd bmcconfig_cmd].each do |param|
      it "has a #{param} parameter" do
        expect(described_class.attrtype(param)).to eq(:param)
      end
    end

    [:community].each do |prop|
      it "has a #{prop} property" do
        expect(described_class.attrtype(prop)).to eq(:property)
      end
    end
  end

  describe 'when validating values' do
    it 'defaults lan_channel to 1 for non-integer title' do
      resource = described_class.new(name: 'mysnmp')
      expect(resource[:lan_channel]).to eq(1)
    end

    it 'derives lan_channel from integer title' do
      resource = described_class.new(name: '2')
      expect(resource[:lan_channel]).to eq(2)
    end

    it 'defaults community to public' do
      resource = described_class.new(name: 'test')
      expect(resource[:community]).to eq('public')
    end

    it 'accepts custom community string' do
      resource = described_class.new(name: 'test', community: 'secret')
      expect(resource[:community]).to eq('secret')
    end
  end
end
