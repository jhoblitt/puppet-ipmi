# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/freeipmi'
require 'puppet_x/ipmi/provider/network_logic'

Puppet::Type.type(:ipmi_network).provide(
  :freeipmi,
  parent: PuppetX::Ipmi::Provider::Freeipmi
) do
  desc 'Manage BMC network configuration via freeipmi (bmc-config)'

  commands bmcconfig: 'bmc-config'

  include PuppetX::Ipmi::Provider::NetworkLogic

  # @return [Hash<Symbol, String>] field => bmc-config Lan_Conf key
  def self.lan_conf_keys
    { source: 'IP_Address_Source', ip: 'IP_Address', netmask: 'Subnet_Mask', gateway: 'Default_Gateway_IP_Address' }
  end

  # @return [Hash<Symbol, String>] source symbol => bmc-config value
  def self.lan_conf_sources
    { dhcp: 'Use_DHCP', static: 'Static' }
  end

  # @param field [Symbol] :source, :ip, :netmask or :gateway
  # @return [String, nil]
  def lan_get(field)
    bmc_config_get('Lan_Conf', self.class.lan_conf_keys.fetch(field), channel: lan_channel)
  end

  # @param field [Symbol] :source, :ip, :netmask or :gateway
  # @param value [String, Symbol] :dhcp or :static for :source
  # @return [void]
  def lan_set(field, value)
    value = self.class.lan_conf_sources.fetch(value.to_sym) if field == :source
    bmc_config_set('Lan_Conf', self.class.lan_conf_keys.fetch(field), value.to_s, channel: lan_channel)
    invalidate_section_cache!('Lan_Conf', channel: lan_channel)
  end
end
