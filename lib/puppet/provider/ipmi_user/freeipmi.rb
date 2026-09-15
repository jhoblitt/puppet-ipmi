# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/freeipmi'
require 'puppet_x/ipmi/provider/user_logic'

Puppet::Type.type(:ipmi_user).provide(
  :freeipmi,
  parent: PuppetX::Ipmi::Provider::Freeipmi
) do
  desc 'Manage BMC user accounts via freeipmi (bmc-config)'

  commands bmcconfig: 'bmc-config'

  include PuppetX::Ipmi::Provider::UserLogic

  # @return [Hash<Integer, String>] mapping of privilege numbers to bmc-config names
  def self.privilege_names
    { 4 => 'Administrator', 3 => 'Operator', 2 => 'User', 1 => 'Callback', 15 => 'No_Access' }
  end

  # @return [Boolean] true when bmc-config reports a username as unset
  def self.unset_name?(name)
    ['<username-not-set-yet>', 'NULL'].include?(name)
  end

  # Parse the output of a full `bmc-config --checkout`.
  #
  # @param output [String, nil]
  # @return [Array<Hash>] entries with :id, :name, :priv and :enabled
  def self.parse_checkout(output)
    users = {}
    current = nil
    output.to_s.each_line do |line|
      if line =~ %r{^\s*Section\s+User(\d+)}i
        current = { id: Regexp.last_match(1).to_i, name: '', priv: 0, enabled: false }
        users[current[:id]] = current
      elsif current && line =~ %r{^\s*Username\s+(.+)$}
        name = Regexp.last_match(1).strip
        current[:name] = name unless unset_name?(name)
      elsif current && line =~ %r{^\s*Lan_Privilege_Limit\s+(\S+)}
        current[:priv] = privilege_names.key(Regexp.last_match(1)) || 0
      elsif current && line =~ %r{^\s*Enable_User\s+(\S+)}
        current[:enabled] = Regexp.last_match(1).casecmp?('Yes')
      end
    end
    users.values.sort_by { |u| u[:id] }
  end

  # A checkout accepted at exit status 1 may be truncated (a key failed to
  # read partway through).  A complete checkout ends with an EndSection line
  # and has contiguous User sections from 1; anything shorter would let the
  # allocator hand out a slot that exists but was never reported.
  #
  # @param users [Array<Hash>] parsed user entries
  # @param output [String] raw checkout output
  # @return [Boolean]
  def self.complete_checkout?(users, output)
    ids = users.map { |u| u[:id] }
    ids == (1..ids.max).to_a && output.to_s.rstrip.end_with?('EndSection')
  end

  def self.read_users(channel)
    result = bmcconfig_exec(['--checkout', '--lan-channel-number', channel.to_s], failonfail: false)
    # Exit 1 can mean either "a key was unreadable but checkout is complete" or
    # an early failure with no configuration.  Only accept it when user sections
    # are actually present, and never include the output in error messages
    # because it may contain keys such as Lan_Conf_Security_Keys.
    users = parse_checkout(result)
    complete = result.exitstatus.zero? || (result.exitstatus == 1 && !users.empty? && complete_checkout?(users, result))
    raise Puppet::Error, "bmc-config --checkout failed (exit #{result.exitstatus})" unless complete

    users
  end

  def self.write_name(channel, id, name)
    bmc_config_set("User#{id}", 'Username', name.to_s, channel: channel)
  end

  def self.write_password(channel, id, password)
    bmc_config_set("User#{id}", 'Password', password, channel: channel, sensitive: true)
  end

  # `bmc-config --diff` prints a `UserN:Password - ...` mismatch line only
  # when the password differs, and that line echoes the password, so the
  # output must never be logged.
  def self.password_matches?(_channel, id, password)
    section = "User#{id}"
    result = bmcconfig_exec(
      ['--diff', '--key-pair', "#{section}:Password=#{password}"],
      failonfail: false,
      sensitive: true
    )
    result.exitstatus.zero? && result !~ %r{^#{section}:Password\b}
  end

  def self.write_priv(channel, id, priv)
    bmc_config_set("User#{id}", 'Lan_Privilege_Limit', privilege_names.fetch(priv), channel: channel)
  end

  def self.write_access(channel, id, enabled, priv)
    section = "User#{id}"
    flag = 'No'
    flag = 'Yes' if enabled
    # Set the privilege limit before enabling so the slot never sits enabled
    # at its old privilege, mirroring the ipmitool backend's order.
    write_priv(channel, id, priv)
    bmc_config_set(section, 'Enable_User', flag, channel: channel)
    bmc_config_set(section, 'Lan_Enable_IPMI_Msgs', flag, channel: channel)
    bmc_config_set(section, 'Lan_Enable_Link_Auth', flag, channel: channel)
    bmc_config_set(section, 'SOL_Payload_Access', flag, channel: channel)
  end
end
