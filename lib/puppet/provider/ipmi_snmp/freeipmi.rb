# frozen_string_literal: true

require 'puppet'
require File.join(File.dirname(__FILE__), '..', 'ipmi')

Puppet::Type.type(:ipmi_snmp).provide(
  :freeipmi,
  parent: Puppet::Provider::Ipmi
) do
  desc 'Manage BMC SNMP community string via freeipmi (bmc-config)'

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

  def community
    bmc_config_get("Lan_Channel:#{lan_channel}", 'Community_String')
  end

  def community=(val)
    bmc_config_set("Lan_Channel:#{lan_channel}", 'Community_String', val)
  end
end
