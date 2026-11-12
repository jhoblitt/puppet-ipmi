# frozen_string_literal: true

require 'resolv'
require 'puppet_x/ipmi/lan_channel'

Puppet::Type.newtype(:ipmi_network) do
  include PuppetX::Ipmi::LanChannel

  @doc = <<-DOC
    @summary
      Manages BMC network configuration via IPMI.

    Supports both ipmitool and freeipmi backends.  Each property is
    independently managed - leave a property unset to skip management
    of that setting.

    The lan channel is derived from the title when it is an integer.
    Otherwise it defaults to 1 when declared directly. The ipmi class can
    inject the node's ipmi.default.channel fact or ipmi::default_channel.

    Two resources may not target the same LAN channel; doing so will fail
    the pre-run check instead of fighting on every run.

    @example Configure DHCP on channel 1
      ipmi_network { 'lan1':
        type => 'dhcp',
      }

    @example Configure static IP on channel 2
      ipmi_network { 'bmc_network':
        lan_channel => 2,
        type        => 'static',
        ip          => '192.168.1.100',
        netmask     => '255.255.255.0',
        gateway     => '192.168.1.1',
      }
  DOC

  newparam(:name, namevar: true) do
    desc 'Resource title. When it is an integer, the lan channel is derived automatically.'
  end

  newproperty(:type) do
    desc 'IP address source: dhcp or static.  No default; leave unset to skip managing this property.'
    newvalues(:dhcp, :static)
  end

  newproperty(:ip) do
    desc 'IP address for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid IP address: #{value}" unless value.to_s =~ Resolv::IPv4::Regex
    end
  end

  newproperty(:netmask) do
    desc 'Subnet mask for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid netmask: #{value}" unless value.to_s =~ Resolv::IPv4::Regex
    end
  end

  newproperty(:gateway) do
    desc 'Default gateway for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid gateway: #{value}" unless value.to_s =~ Resolv::IPv4::Regex
    end
  end

  validate do
    if self[:type] == :dhcp
      %i[ip netmask gateway].each do |prop|
        raise Puppet::Error, "#{prop} cannot be set when type is 'dhcp'" if self[prop]
      end
    elsif self[:type] == :static
      # Switching to static without a complete address can strand the BMC on
      # a stored or garbage configuration.  ip and netmask must come as a
      # pair; the gateway stays optional because out-of-band management
      # networks often route nowhere.  Fail at catalog compile time rather
      # than mid-transaction on a remote box.
      missing = %i[ip netmask].reject { |prop| self[prop] }
      raise Puppet::Error, "ip and netmask must both be set when type is 'static' (missing: #{missing.join(', ')})" unless missing.empty?
    end
  end
end
