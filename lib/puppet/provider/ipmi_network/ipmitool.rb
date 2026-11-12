# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/ipmitool'
require 'puppet_x/ipmi/provider/network_logic'

Puppet::Type.type(:ipmi_network).provide(
  :ipmitool,
  parent: PuppetX::Ipmi::Provider::Ipmitool,
) do
  desc 'Manage BMC network configuration via ipmitool'

  commands ipmitool: 'ipmitool'
  defaultfor kernel: 'Linux'

  include PuppetX::Ipmi::Provider::NetworkLogic

  # @return [Hash<Symbol, String>] field => `ipmitool lan print` label
  def self.lan_print_keys
    { source: 'IP Address Source', ip: 'IP Address', netmask: 'Subnet Mask', gateway: 'Default Gateway IP' }
  end

  # @return [Hash<Symbol, Array<String>>] field => `ipmitool lan set` words
  def self.lan_set_words
    { ip: ['ipaddr'], netmask: ['netmask'], gateway: %w[defgw ipaddr] }
  end

  # @param field [Symbol] :source, :ip, :netmask or :gateway
  # @return [String, nil]
  def lan_get(field)
    parse_lan_print[self.class.lan_print_keys.fetch(field)]
  end

  # @param field [Symbol] :source, :ip, :netmask or :gateway
  # @param value [String, Symbol] :dhcp or :static for :source
  # @return [void]
  def lan_set(field, value)
    argv = ['lan', 'set', lan_channel.to_s]
    argv += if field == :source
              ['ipsrc', value.to_s]
            else
              self.class.lan_set_words.fetch(field) + [value.to_s]
            end
    ipmitool_exec(argv)
    invalidate_lan_print_cache!
  end
end
