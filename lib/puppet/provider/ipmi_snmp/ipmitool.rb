# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/ipmitool'

Puppet::Type.type(:ipmi_snmp).provide(
  :ipmitool,
  parent: PuppetX::Ipmi::Provider::Ipmitool,
) do
  desc 'Manage BMC SNMP community string via ipmitool'

  commands ipmitool: 'ipmitool'
  defaultfor kernel: 'Linux'

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  # @return [String, nil] current SNMP community string
  def community
    parse_lan_print['SNMP Community String']
  end

  # The community never goes on the command line, where any local user can
  # read it from ps or /proc/<pid>/cmdline.  `lan set <channel> snmp` takes
  # it only as an argument and never prompts, so it is run through `ipmitool
  # exec` and a mode 0600 batch file.  It prints the community it sets,
  # which is kept out of the error when the write fails.
  #
  # `lan set` takes any value starting with "help" as a request for usage
  # (a strncmp in ipmi_lan_set, ipmitool 1.8.18): it prints that, exits 0
  # and sets nothing, so such a community would never converge.
  #
  # @param val [String] community string to set
  # @return [void]
  def community=(val)
    raise Puppet::Error, 'ipmitool cannot set an SNMP community starting with "help", which it takes as a request for help' if val.to_s.start_with?('help')

    line = "lan set #{lan_channel} snmp #{self.class.exec_token(val.to_s, 'an SNMP community')}\n"
    self.class.with_secret_file(line) do |path|
      ipmitool_exec(['exec', path], sensitive: true, redact: [val.to_s])
    end
    invalidate_lan_print_cache!
  end
end
