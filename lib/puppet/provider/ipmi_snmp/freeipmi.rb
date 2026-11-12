# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/freeipmi'

Puppet::Type.type(:ipmi_snmp).provide(
  :freeipmi,
  parent: PuppetX::Ipmi::Provider::Freeipmi,
) do
  desc 'Manage BMC SNMP community string via freeipmi (ipmi-pef-config)'

  commands pefconfig: 'ipmi-pef-config'

  # ipmi-pef-config is the same ipmi-config front end as bmc-config, so the
  # base helpers apply; only the binary differs.
  def self.config_command
    :pefconfig
  end

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  # @return [String, nil] current SNMP community string
  def community
    bmc_config_get('Community_String', 'Community_String', channel: lan_channel)
  end

  # The community goes through a mode 0600 config file, never the command
  # line.
  #
  # @param val [String] community string to set
  # @return [void]
  def community=(val)
    self.class.bmc_config_secret('--commit', 'Community_String', 'Community_String', val.to_s,
                                 extra_argv: ['--lan-channel-number', lan_channel.to_s])
  end
end
