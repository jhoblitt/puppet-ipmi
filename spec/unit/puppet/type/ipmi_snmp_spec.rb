# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_snmp'

describe Puppet::Type.type(:ipmi_snmp) do
  describe 'when validating attributes' do
    %i[name lan_channel].each do |param|
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
      Facter.stubs(:value).with(:kernel).returns('Linux')
      Facter.stubs(:value).with('ipmi.default.channel').returns(nil)
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

    it 'does not read compiler-local facts for the channel default' do
      Facter.expects(:value).with('ipmi.default.channel').never
      expect(described_class.new(name: 'test')[:lan_channel]).to eq(1)
    end

    it 'accepts custom community string' do
      resource = described_class.new(name: 'test', community: 'secret')
      expect(resource[:community]).to eq('secret')
    end
  end

  describe 'pre-run duplicate channel check' do
    it 'raises when two resources target the same channel' do
      resource_a = described_class.new(name: 'snmp_a', lan_channel: 1, community: 'alpha')
      resource_b = described_class.new(name: 'snmp_b', lan_channel: 1, community: 'beta')
      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource_a)
      catalog.add_resource(resource_b)

      expect { resource_a.pre_run_check }.to raise_error(Puppet::Error, %r{Multiple ipmi_snmp resources target channel 1})
    end

    it 'allows resources targeting different channels' do
      resource_a = described_class.new(name: 'snmp_a', lan_channel: 1, community: 'alpha')
      resource_b = described_class.new(name: 'snmp_b', lan_channel: 2, community: 'beta')
      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource_a)
      catalog.add_resource(resource_b)

      expect { resource_a.pre_run_check }.not_to raise_error
    end
  end
end
