# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi'
require 'puppet/provider'

# Base provider for IPMI-managed resources.
#
# Provides generic helpers shared across all IPMI tool implementations.
# Tool-specific execution helpers live in PuppetX::Ipmi::Provider::Ipmitool
# and PuppetX::Ipmi::Provider::Freeipmi.
class PuppetX::Ipmi::Provider::Base < Puppet::Provider
  # Parse colon-separated key-value output (lines like "Key  : Value").
  # Used by any provider that reads structured output in this format.
  #
  # @param output [String] command output to parse
  # @return [Hash<String, String>]
  def self.parse_colon_kv(output)
    result = {}
    return result if output.nil? || output.empty?

    output.each_line do |line|
      next unless line.include?(':')

      parts = line.split(':', 2)
      key = parts[0].strip
      value = parts[1].strip
      result[key] = value unless key.empty?
    end
    result
  end

  # @see PuppetX::Ipmi::Provider::Base.parse_colon_kv
  def parse_colon_kv(output)
    self.class.parse_colon_kv(output)
  end

  # @return [Integer] IPMI channel for user management
  def channel
    @resource[:channel]
  end

  # @return [Integer] IPMI LAN channel for network/SNMP management
  def lan_channel
    @resource[:lan_channel]
  end
end
