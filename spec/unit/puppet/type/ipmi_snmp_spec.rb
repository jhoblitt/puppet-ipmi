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
    it 'rejects an empty community' do
      expect { described_class.new(name: 'mysnmp', community: '') }
        .to raise_error(Puppet::Error, %r{non-empty})
    end

    it 'rejects a community longer than 18 characters' do
      expect { described_class.new(name: 'mysnmp', community: 'a' * 19) }
        .to raise_error(Puppet::Error, %r{18 bytes})
    end

    it 'accepts a community of exactly 18 characters' do
      expect { described_class.new(name: 'mysnmp', community: 'a' * 18) }.not_to raise_error
    end

    it 'marks the community property as sensitive' do
      expect(described_class.new(name: 'mysnmp').parameter(:community).is_sensitive).to be(true)
    end

    it 'rejects a lan_channel with a trailing newline' do
      expect { described_class.new(name: 'mysnmp', lan_channel: "1\nx") }
        .to raise_error(Puppet::Error, %r{lan_channel})
    end

    it 'does not derive a channel from a multi-line title' do
      expect(PuppetX::Ipmi::LanChannel.default_channel("5\nx")).to eq(1)
    end

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

    it 'accepts a community of 18 bytes' do
      expect(described_class.new(name: 'test', community: "#{'é' * 8}ab")[:community]).to eq("#{'é' * 8}ab")
    end

    it 'rejects a community over 18 bytes even when it is shorter in characters, without echoing it' do
      expect { described_class.new(name: 'test', community: 'é' * 10) }
        .to raise_error(Puppet::Error, %r{18 bytes or fewer}) { |e| expect(e.message).not_to include('é') }
    end

    # Both backends read the community back with surrounding whitespace
    # stripped, so such a community would never be in sync.
    [' lead', 'trail ', "tab\t", "\nline"].each do |community|
      it "rejects the community #{community.inspect}, which starts or ends with whitespace, without echoing it" do
        expect { described_class.new(name: 'test', community: community) }
          .to raise_error(Puppet::Error, %r{community must not start or end with whitespace}) { |e| expect(e.message).not_to include(community.strip) }
      end
    end

    it 'accepts a community with a space inside it' do
      expect(described_class.new(name: 'test', community: 'my community')[:community]).to eq('my community')
    end

    it 'treats the community as sensitive even when it is not wrapped' do
      resource = described_class.new(name: 'test', community: 'secret')
      expect(resource.parameter(:community).sensitive).to be(true)
    end

    it 'treats the default community as sensitive' do
      resource = described_class.new(name: 'test')
      expect(resource.parameter(:community).sensitive).to be(true)
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
