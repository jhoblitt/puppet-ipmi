# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/freeipmi'
require 'puppet_x/ipmi/provider/user_logic'

Puppet::Type.type(:ipmi_user).provide(
  :freeipmi,
  parent: PuppetX::Ipmi::Provider::Freeipmi,
) do
  desc 'Manage BMC user accounts via freeipmi (bmc-config)'

  commands bmcconfig: 'bmc-config'

  include PuppetX::Ipmi::Provider::UserLogic

  # @return [Hash<Integer, String>] mapping of privilege numbers to bmc-config names
  def self.privilege_names
    { 5 => 'OEM_Proprietary', 4 => 'Administrator', 3 => 'Operator', 2 => 'User', 1 => 'Callback', 15 => 'No_Access' }
  end

  # @return [Boolean] true when bmc-config reports a username as unset
  def self.unset_name?(name)
    ['<username-not-set-yet>', 'NULL'].include?(name)
  end

  # Parse the output of a full `bmc-config --checkout`.
  #
  # bmc-config prints no value for a privilege limit that is no privilege
  # level, and comments out an `Enable_User` the BMC does not report.
  #
  # @param output [String, nil]
  # @return [Array<Hash>] entries with :id, :name, :priv and :status
  def self.parse_checkout(output)
    users = {}
    current = nil
    output.to_s.each_line do |line|
      if line =~ %r{^\s*Section\s+User(\d+)}i
        current = { id: Regexp.last_match(1).to_i, name: '', priv: 0, status: :unknown }
        users[current[:id]] = current
      elsif current && line =~ %r{^\s*Username\s+(.+)$}
        name = Regexp.last_match(1).strip
        current[:name] = name unless unset_name?(name)
      elsif current && line =~ %r{^\s*Lan_Privilege_Limit\s+(\S+)}
        current[:priv] = privilege_names.key(Regexp.last_match(1))
      elsif current && line =~ %r{^\s*Enable_User\s+(\S+)}
        current[:status] = { 'yes' => :enabled, 'no' => :disabled }.fetch(Regexp.last_match(1).downcase, :unknown)
      end
    end
    users.values.sort_by { |u| u[:id] }
  end

  # With more than one LAN channel, a verbose checkout gives each user key
  # that is per LAN channel once per channel, as `<key>_Channel_<n>`
  # (ipmi_config_section_multi_channel_add_key, FreeIPMI 1.0.1 and later).
  # With one, it gives only the plain key, and the channel number does not
  # show; the channels resources name are read then.
  #
  # A key bmc-config cannot read is left out and the checkout exits 1, so
  # a probe that failed could look like fewer LAN channels.  Exit 1 is also
  # routine: --verbose adds the Serial_ keys, which cannot be read on a BMC
  # with no serial channel.  A second --verbose names each key left out
  # (`## Unable to checkout User1:<key>`, ipmi_config_checkout_section in
  # ipmi-config-checkout.c, FreeIPMI 1.6.x), so the probe is trusted only
  # when it exits 0, or exits 1 with the section complete and only Serial_
  # keys left out.
  #
  # @return [Array<Integer>] the LAN channels bmc-config finds
  def self.lan_channels
    result = bmcconfig_exec(['--checkout', '--verbose', '--verbose', '--section', 'User1'], failonfail: false)
    output = result.to_s
    unread = output.scan(%r{^\s*## Unable to checkout User1:(\S+)}).flatten.reject { |key| key.start_with?('Serial_') }
    unless result.exitstatus.zero? || (result.exitstatus == 1 && output.rstrip.end_with?('EndSection') && unread.empty?)
      detail = ''
      detail = ": could not read #{unread.map { |key| "User1:#{key}" }.join(', ')}" unless unread.empty?
      raise Puppet::Error, "bmc-config --checkout --section User1 failed (exit #{result.exitstatus}), so its LAN channels are unknown#{detail}"
    end

    output.scan(%r{^\s*(?:##\s*)?Lan_Privilege_Limit_Channel_(\d+)\s}).flatten.map(&:to_i).uniq.sort
  end

  # Each channel is checked out on its own with --lan-channel-number, which
  # selects the channel of the plain per-channel keys.  The name and
  # `Enable_User` are the account's, so they come from the first.
  def self.read_table(channels)
    lists = channels.to_h { |channel| [channel, read_users(channel)] }
    statuses = lists.fetch(channels.first).to_h { |u| [u[:id], u[:status]] }
    PuppetX::Ipmi::Provider::UserLogic.merge(lists, statuses)
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

  # The name goes on the command line, which cannot carry a NUL byte, and
  # bmc-config keeps only its first word.
  def self.check_name(channel, id, name)
    raise Puppet::Error, "User#{id}:Username: freeipmi cannot store a value containing a NUL byte" if name.to_s.include?("\0")

    bmc_config_set_argv("User#{id}", 'Username', name.to_s, channel: channel)
  end

  def self.write_name(channel, id, name)
    check_name(channel, id, name)
    bmc_config_set("User#{id}", 'Username', name.to_s, channel: channel)
  end

  # bmc-config's Password key takes up to 20 bytes and stores more than 16
  # in the 20-byte form, on a BMC that supports it (password_validate and
  # password_commit in ipmi-config-category-core-user-sections.c, FreeIPMI
  # 1.6.x; NEWS dates it to 0.8.1); Password20 is a legacy alias for the
  # same write.
  #
  # @see PuppetX::Ipmi::Provider::Freeipmi.check_secret
  def self.check_password(_channel, id, password)
    raise Puppet::Error, "User#{id}:Password: freeipmi cannot store a password longer than 20 bytes" if password.to_s.bytesize > 20

    check_secret("User#{id}", 'Password', password)
  end

  # The password goes through a mode 0600 config file, never the command
  # line.
  def self.write_password(channel, id, password)
    check_password(channel, id, password)
    bmc_config_secret('--commit', "User#{id}", 'Password', password, extra_argv: ['--lan-channel-number', channel.to_s])
  end

  # `bmc-config --diff` prints a `UserN:Password - ...` mismatch line only
  # when the password differs, and that line echoes the password, so the
  # output must never be logged.
  def self.password_matches?(_channel, id, password)
    section = "User#{id}"
    result = bmc_config_secret('--diff', section, 'Password', password, failonfail: false)
    result.exitstatus.zero? && result !~ %r{^#{section}:Password\b}
  end

  def self.write_priv(channel, id, priv)
    bmc_config_set("User#{id}", 'Lan_Privilege_Limit', privilege_names.fetch(priv), channel: channel)
  end

  # Enable_User is the account's, but bmc-config reads it through a channel.
  #
  # @return [#call] enables the account with true and disables it with false
  def self.enabled_writer(channel, id)
    ->(on) { bmc_config_set("User#{id}", 'Enable_User', { true => 'Yes', false => 'No' }.fetch(on), channel: channel) }
  end

  # Fails closed (see UserLogic.enable_failing_closed), in the ipmitool
  # backend's order.
  def self.grant_access(channel, id, priv)
    section = "User#{id}"
    enable_failing_closed(id, set_priv: -> { write_priv(channel, id, priv) }, set_enabled: enabled_writer(channel, id)) do
      bmc_config_set(section, 'SOL_Payload_Access', 'Yes', channel: channel)
      bmc_config_set(section, 'Lan_Enable_IPMI_Msgs', 'Yes', channel: channel)
      bmc_config_set(section, 'Lan_Enable_Link_Auth', 'Yes', channel: channel)
    end
  end

  # Fails closed (see UserLogic.disable_failing_closed).  Privilege, channel
  # and SOL access are revoked on each channel before Enable_User is
  # cleared, because BMCs ignore or refuse permission changes on a disabled
  # user.
  def self.revoke_access(channels, id, already_disabled: false)
    section = "User#{id}"
    revokes = channels.flat_map do |channel|
      [-> { write_priv(channel, id, PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV) }] +
        %w[Lan_Enable_IPMI_Msgs Lan_Enable_Link_Auth SOL_Payload_Access].map { |key| -> { bmc_config_set(section, key, 'No', channel: channel) } }
    end
    disable_failing_closed(id, revokes: revokes, set_enabled: enabled_writer(channels.first, id), already_disabled: already_disabled)
  end
end
