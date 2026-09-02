# frozen_string_literal: true

require 'puppet'
require File.join(File.dirname(__FILE__), '..', 'ipmi')

Puppet::Type.type(:ipmi_network).provide(
  :freeipmi,
  parent: Puppet::Provider::Ipmi
) do
  desc 'Manage BMC network configuration via freeipmi (bmc-config)'

  confine commands: { bmcconfig: 'bmc-config' }

  def bmcconfig_cmd
    @resource[:bmcconfig_cmd] || '/usr/sbin/bmc-config'
  end

  def bmcconfig_exec(args, failonfail: false)
    Puppet::Util::Execution.execute("#{bmcconfig_cmd} #{args}", failonfail: failonfail)
  end

  def lan_channel
    @resource[:lan_channel]
  end

  # Parse bmc-config checkout output for a given section and key.
  def bmc_config_get(section, key)
    output = bmcconfig_exec("--checkout --section #{section} 2>/dev/null")
    return nil if output.nil? || output.empty?

    output.each_line do |line|
      stripped = line.strip
      return Regexp.last_match(1).strip if stripped =~ %r{^#{Regexp.escape(key)}\s+(.+)$}
    end
    nil
  end

  def bmc_config_set(section, key, value)
    bmcconfig_exec(
      "--commit --key-pair #{shellescape("#{section}:#{key}=#{value}")}",
      failonfail: true
    )
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  def type
    val = bmc_config_get("Lan_Channel:#{lan_channel}", 'IP_Address_Source')
    return nil if val.nil?

    val =~ %r{DHCP}i ? :dhcp : :static
  end

  def type=(val)
    source = val.to_s == 'dhcp' ? 'Use_DHCP' : 'Static'
    bmc_config_set("Lan_Channel:#{lan_channel}", 'IP_Address_Source', source)
  end

  def ip
    bmc_config_get("Lan_Channel:#{lan_channel}", 'IP_Address')
  end

  def ip=(val)
    bmc_config_set("Lan_Channel:#{lan_channel}", 'IP_Address', val)
  end

  def netmask
    bmc_config_get("Lan_Channel:#{lan_channel}", 'Subnet_Mask')
  end

  def netmask=(val)
    bmc_config_set("Lan_Channel:#{lan_channel}", 'Subnet_Mask', val)
  end

  def gateway
    bmc_config_get("Lan_Channel:#{lan_channel}", 'Default_Gateway_IP_Address')
  end

  def gateway=(val)
    bmc_config_set("Lan_Channel:#{lan_channel}", 'Default_Gateway_IP_Address', val)
  end
end
