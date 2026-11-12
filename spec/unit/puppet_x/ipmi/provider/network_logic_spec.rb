# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/ipmi/provider/network_logic'

describe PuppetX::Ipmi::Provider::NetworkLogic do
  let(:backend) do
    Class.new do
      include PuppetX::Ipmi::Provider::NetworkLogic

      attr_accessor :resource, :values, :writes

      def initialize
        @values = {}
        @writes = []
      end

      def lan_get(field)
        values[field]
      end

      def lan_set(field, value)
        writes << [field, value]
        values[field] = value
      end
    end
  end
  let(:provider) { backend.new }

  describe '#type' do
    it 'is nil when the source is unreadable' do
      expect(provider.type).to be_nil
    end

    ['DHCP Address', 'Use_DHCP', 'use_dhcp'].each do |source|
      it "is :dhcp for #{source.inspect}" do
        provider.values[:source] = source

        expect(provider.type).to eq(:dhcp)
      end
    end

    ['Static Address', 'Static', 'static', 'BIOS Assigned Address'].each do |source|
      it "is :static for #{source.inspect}" do
        provider.values[:source] = source

        expect(provider.type).to eq(:static)
      end
    end
  end

  describe 'plain properties' do
    { ip: '10.0.0.1', netmask: '255.255.255.0', gateway: '10.0.0.254' }.each do |field, value|
      it "reads #{field}" do
        provider.values[field] = value

        expect(provider.public_send(field)).to eq(value)
      end

      it "writes #{field} as a String" do
        provider.public_send(:"#{field}=", value.to_sym)

        expect(provider.writes).to eq([[field, value]])
      end
    end
  end

  describe '#type=' do
    before { provider.resource = { ip: '10.0.0.1', netmask: '255.255.255.0', gateway: '10.0.0.254' } }

    it 'sets dhcp and touches nothing else' do
      provider.type = :dhcp

      expect(provider.writes).to eq([%i[source dhcp]])
    end

    it 're-applies every static field that still differs, after the source' do
      provider.values.merge!(ip: 'stale', netmask: 'stale', gateway: 'stale')

      provider.type = :static

      expect(provider.writes).to eq(
        [%i[source static], [:ip, '10.0.0.1'], [:netmask, '255.255.255.0'], [:gateway, '10.0.0.254']],
      )
    end

    it 'skips fields the BMC already holds' do
      provider.values.merge!(ip: '10.0.0.1', netmask: '255.255.255.0', gateway: 'stale')

      provider.type = :static

      expect(provider.writes).to eq([%i[source static], [:gateway, '10.0.0.254']])
    end

    it 'skips fields the resource does not manage' do
      provider.resource = { ip: '10.0.0.1' }
      provider.values[:ip] = 'stale'

      provider.type = :static

      expect(provider.writes).to eq([%i[source static], [:ip, '10.0.0.1']])
    end

    it 'leaves nothing for the setters to write again' do
      provider.values.merge!(ip: 'stale', netmask: '255.255.255.0', gateway: 'stale')

      provider.type = :static
      provider.ip = '10.0.0.1'
      provider.netmask = '255.255.255.0'
      provider.gateway = '10.0.0.254'

      expect(provider.writes).to eq(
        [%i[source static], [:ip, '10.0.0.1'], [:gateway, '10.0.0.254']],
      )
    end

    it 'does not stop the setters writing a different value' do
      provider.values.merge!(ip: 'stale', netmask: '255.255.255.0', gateway: '10.0.0.254')

      provider.type = :static
      provider.ip = '10.0.0.2'

      expect(provider.writes).to eq([%i[source static], [:ip, '10.0.0.1'], [:ip, '10.0.0.2']])
    end
  end
end
