# frozen_string_literal: true

require 'puppet'
require File.join(File.dirname(__FILE__), '..', 'ipmi')

Puppet::Type.type(:ipmi_network).provide(
  :ipmitool,
  parent: Puppet::Provider::Ipmi
) do
  desc 'Manage BMC network configuration via ipmitool'

  confine commands: { ipmitool: 'ipmitool' }
  defaultfor kernel: 'Linux'

  def ipmitool_cmd
    @resource[:ipmitool_cmd] || '/usr/bin/ipmitool'
  end

  def ipmitool_exec(args, failonfail: false)
    Puppet::Util::Execution.execute("#{ipmitool_cmd} #{args}", failonfail: failonfail)
  end

  def lan_channel
    @resource[:lan_channel]
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  def type
    output = ipmitool_exec("lan print #{lan_channel} 2>/dev/null")
    kv = parse_colon_kv(output)
    source = kv['IP Address Source']
    return nil if source.nil?

    source.include?('DHCP') ? :dhcp : :static
  end

  def type=(val)
    if val.to_s == 'dhcp'
      ipmitool_exec("lan set #{lan_channel} ipsrc dhcp", failonfail: true)
    else
      ipmitool_exec("lan set #{lan_channel} ipsrc static", failonfail: true)
    end
  end

  def ip
    output = ipmitool_exec("lan print #{lan_channel} 2>/dev/null")
    kv = parse_colon_kv(output)
    kv['IP Address']
  end

  def ip=(val)
    ipmitool_exec("lan set #{lan_channel} ipaddr #{val}", failonfail: true)
  end

  def netmask
    output = ipmitool_exec("lan print #{lan_channel} 2>/dev/null")
    kv = parse_colon_kv(output)
    kv['Subnet Mask']
  end

  def netmask=(val)
    ipmitool_exec("lan set #{lan_channel} netmask #{val}", failonfail: true)
  end

  def gateway
    output = ipmitool_exec("lan print #{lan_channel} 2>/dev/null")
    kv = parse_colon_kv(output)
    kv['Default Gateway IP']
  end

  def gateway=(val)
    ipmitool_exec("lan set #{lan_channel} defgw ipaddr #{val}", failonfail: true)
  end
end
