# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/ipmi_network'

# Runs real catalogs through the real providers, with each provider's exec
# helper answered by an in-memory LAN configuration, so output parsing,
# caching and Puppet's property sync all take part.
describe 'ipmi_network catalog application' do
  let(:lan) { { source: :dhcp, ip: '10.0.0.5', netmask: '255.255.0.0', gateway: '10.0.0.1' } }
  let(:writes) { [] }
  # Address some BMCs load from storage when the source changes to static.
  let(:stored_static) { {} }
  let(:state_dir) { Dir.mktmpdir }

  before { Puppet[:statedir] = state_dir }
  after { FileUtils.rm_rf(state_dir) }

  def static_address
    { ip: '192.168.1.100', netmask: '255.255.255.0', gateway: '192.168.1.1' }
  end

  def apply(backend)
    type = Puppet::Type.type(:ipmi_network)
    type.provider(backend).stubs(:suitable?).returns(true)
    resource = type.new({ name: 'lan1', lan_channel: 1, provider: backend, type: :static }.merge(static_address))
    exec_helper = { ipmitool: :ipmitool_exec, freeipmi: :bmcconfig_exec }.fetch(backend)
    fake = method(:"fake_#{backend}")
    resource.provider.define_singleton_method(exec_helper) { |argv, **| fake.call(argv) }

    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource(resource)
    catalog.apply.report
  end

  def store(field, value)
    lan[field] = value
    lan.merge!(stored_static) if field == :source && value == :static
    ''
  end

  def fake_ipmitool(argv)
    return ipmitool_lan_print if argv == %w[lan print 1]

    writes << argv
    field = { 'ipsrc' => :source, 'ipaddr' => :ip, 'netmask' => :netmask, 'defgw' => :gateway }.fetch(argv[3])
    store(field, (field == :source) ? argv.last.to_sym : argv.last)
  end

  def ipmitool_lan_print
    <<~OUTPUT
      IP Address Source       : #{(lan[:source] == :dhcp) ? 'DHCP Address' : 'Static Address'}
      IP Address              : #{lan[:ip]}
      Subnet Mask             : #{lan[:netmask]}
      Default Gateway IP      : #{lan[:gateway]}
    OUTPUT
  end

  def fake_freeipmi(argv)
    return bmc_config_lan_conf if argv == %w[--checkout --section Lan_Conf --lan-channel-number 1]

    writes << argv
    key, value = argv[2].delete_prefix('Lan_Conf:').split('=', 2)
    field = { 'IP_Address_Source' => :source, 'IP_Address' => :ip, 'Subnet_Mask' => :netmask, 'Default_Gateway_IP_Address' => :gateway }.fetch(key)
    store(field, (field == :source) ? { 'Use_DHCP' => :dhcp, 'Static' => :static }.fetch(value) : value)
  end

  def bmc_config_lan_conf
    <<~OUTPUT
      Section Lan_Conf
              IP_Address_Source                             #{(lan[:source] == :dhcp) ? 'Use_DHCP' : 'Static'}
              IP_Address                                    #{lan[:ip]}
              Subnet_Mask                                   #{lan[:netmask]}
              Default_Gateway_IP_Address                    #{lan[:gateway]}
      EndSection
    OUTPUT
  end

  {
    ipmitool: [
      %w[lan set 1 ipsrc static],
      %w[lan set 1 ipaddr 192.168.1.100],
      %w[lan set 1 netmask 255.255.255.0],
      %w[lan set 1 defgw ipaddr 192.168.1.1],
    ],
    freeipmi: [
      %w[--commit --key-pair Lan_Conf:IP_Address_Source=Static --lan-channel-number 1],
      %w[--commit --key-pair Lan_Conf:IP_Address=192.168.1.100 --lan-channel-number 1],
      %w[--commit --key-pair Lan_Conf:Subnet_Mask=255.255.255.0 --lan-channel-number 1],
      %w[--commit --key-pair Lan_Conf:Default_Gateway_IP_Address=192.168.1.1 --lan-channel-number 1],
    ],
  }.each do |backend, expected_writes|
    context "with the #{backend} provider" do
      it 'writes each field once when switching from DHCP to a new static address, then stays quiet' do
        report = apply(backend)

        expect(report.resource_statuses.values.count(&:failed)).to eq(0)
        expect(writes).to eq(expected_writes)
        expect(lan).to eq(static_address.merge(source: :static))

        writes.clear
        expect(apply(backend).resource_statuses.values.count(&:changed)).to eq(0)
        expect(writes).to be_empty
      end

      context 'when the BMC restores the wanted address on switching to static' do
        let(:stored_static) { static_address }

        it 'writes only the source' do
          report = apply(backend)

          expect(report.resource_statuses.values.count(&:failed)).to eq(0)
          expect(writes).to eq(expected_writes.take(1))
          expect(lan).to eq(static_address.merge(source: :static))
        end
      end
    end
  end
end
