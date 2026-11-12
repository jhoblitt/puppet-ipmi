# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/ipmitool'
require 'puppet_x/ipmi/provider/user_logic'

Puppet::Type.type(:ipmi_user).provide(
  :ipmitool,
  parent: PuppetX::Ipmi::Provider::Ipmitool,
) do
  desc 'Manage BMC user accounts via ipmitool'

  commands ipmitool: 'ipmitool'
  defaultfor kernel: 'Linux'

  include PuppetX::Ipmi::Provider::UserLogic

  # @return [Hash<Integer, String>] mapping of privilege numbers to ipmitool names
  def self.privilege_names
    { 5 => 'OEM', 4 => 'ADMINISTRATOR', 3 => 'OPERATOR', 2 => 'USER', 1 => 'CALLBACK', 15 => 'NO ACCESS' }
  end

  # The channels a LAN channel can be: ipmitool accepts channel numbers 0 to
  # 11, 14 and 15 (is_ipmi_channel_num in lib/helper.c, 1.8.18), and 0 is
  # IPMB, 14 the current channel and 15 the system interface.
  #
  # @return [Range<Integer>]
  def self.probed_channels
    (1..11)
  end

  # @return [Array<String>] the media ipmitool's own LAN commands accept
  #   (is_lan_channel in lib/ipmi_lanp.c, 1.8.18), as `channel info` prints
  #   them
  def self.lan_media
    ['802.3 LAN', 'Other LAN']
  end

  # @param text [String] a privilege as ipmitool prints it
  # @return [Integer, nil] its number: `Unknown (0x00)` is 0; nil when the
  #   text is not one ipmitool prints
  def self.parse_priv(text)
    privilege_names.key(text) || text[%r{\AUnknown \(0x(\h+)\)\z}, 1]&.hex
  end

  # Parse `ipmitool user list <channel>` output.
  #
  # @param output [String, nil]
  # @return [Array<Hash>] entries with :id, :name and :priv
  def self.parse_user_list(output)
    users = []
    return users if output.nil? || output.empty?

    output.each_line do |line|
      next unless line.strip =~ %r{^(\d+)\s+(.*?)\s+(true|false)\s+(true|false)\s+(true|false)\s+(.+)$}

      name = Regexp.last_match(2).strip
      name = '' if name == '(Empty User)'

      users << {
        id: Regexp.last_match(1).to_i,
        name: name,
        priv: parse_priv(Regexp.last_match(6).strip),
      }
    end
    users
  end

  # Parse the `Enable Status` of every slot from `ipmitool channel getaccess
  # <channel>`, which prints one record per slot.
  #
  # Only `enabled` and `disabled` are known.  BMCs that do not implement the
  # IPMI 2.0 enable bits report `unknown`, and ipmitool before 1.8.18 prints
  # no `Enable Status` line.
  #
  # @param output [String, nil]
  # @return [Hash{Integer => Symbol}] status by slot id
  def self.parse_enable_statuses(output)
    statuses = {}
    id = nil
    output.to_s.each_line do |line|
      key, value = line.split(':', 2).map(&:strip)
      id = value.to_i if key == 'User ID'
      statuses[id] = { 'enabled' => :enabled, 'disabled' => :disabled }.fetch(value, :unknown) if key == 'Enable Status' && id
    end
    statuses
  end

  # `channel info` fails for a channel the BMC does not have as it does for
  # any other failure, but names the completion code: ipmi_get_channel_info
  # (lib/ipmi_channel.c, 1.8.18) prints it through eval_ccode (lib/helper.c)
  # as `IPMI command failed: <text>`.  ipmitool's own LAN channel search
  # (ipmi_get_channel_medium) takes 0xCC, invalid data field in request,
  # alone as no such channel, and reports any other code as a failure.
  #
  # @param output [String] the output of a failed `channel info`
  # @return [Boolean]
  def self.no_such_channel?(output)
    output.match?(%r{^IPMI command failed: Invalid data field in request$})
  end

  # A probe that fails for any other reason raises, since skipping the
  # channel would leave its access unrevoked.
  #
  # @return [Array<Integer>] the channels whose medium is a LAN
  def self.lan_channels
    probed_channels.select do |channel|
      result = ipmitool_exec(['channel', 'info', channel.to_s], failonfail: false)
      next lan_media.include?(parse_colon_kv(result)['Channel Medium Type']) if result.exitstatus.zero?
      next false if no_such_channel?(result)

      raise Puppet::Error, "ipmitool channel info #{channel} failed (exit #{result.exitstatus}): #{result.strip}"
    end
  end

  # `user list` prints each slot's privilege on one channel, so it is read
  # on every channel.  It has no enable column, and the enabled state is
  # the account's, so `Enable Status` is read once, for every slot, from
  # `channel getaccess`.
  def self.read_table(channels)
    lists = channels.to_h { |channel| [channel, parse_user_list(ipmitool_exec(['user', 'list', channel.to_s]))] }
    statuses = parse_enable_statuses(ipmitool_exec(['channel', 'getaccess', channels.first.to_s]))
    PuppetX::Ipmi::Provider::UserLogic.merge(lists, statuses)
  end

  # The name goes on the command line, which cannot carry a NUL byte.
  def self.check_name(_channel, _id, name)
    raise Puppet::Error, 'ipmitool cannot set a username containing a NUL byte' if name.to_s.include?("\0")
  end

  def self.write_name(channel, id, name)
    check_name(channel, id, name)
    ipmitool_exec(['user', 'set', 'name', id.to_s, name.to_s])
  end

  # @see write_password
  def self.check_password(_channel, _id, password)
    return exec_token(password, 'a password of 17 to 20 bytes') if password.bytesize > 16

    check_prompt_secret(password)
  end

  # getpass(3) ends a line at a newline and reads it as a C string, so a
  # newline or NUL byte would cut the password short.
  def self.check_prompt_secret(password)
    raise Puppet::Error, 'ipmitool cannot read a password containing a newline or a NUL byte' if password.match?(%r{[\n\0]})
  end

  # A password never goes on the command line, where any local user can
  # read it from ps or /proc/<pid>/cmdline.  Given no password, `user set
  # password` and `user test` prompt for it with getpass(3).  Puppet runs
  # commands in a new session without a controlling terminal, so getpass
  # reads stdin, which comes from a mode 0600 file.
  #
  # The prompt always stores the 16 byte form, so a longer password goes
  # through `ipmitool exec` and a mode 0600 batch file instead.
  def self.write_password(channel, id, password)
    check_password(channel, id, password)

    if password.bytesize <= 16
      with_secret_file("#{password}\n#{password}\n") do |path|
        ipmitool_exec(['user', 'set', 'password', id.to_s], stdinfile: path, sensitive: true, redact: [password])
      end
    else
      with_secret_file("user set password #{id} #{exec_token(password, 'a password of 17 to 20 bytes')} 20\n") do |path|
        ipmitool_exec(['exec', path], sensitive: true, redact: [password])
      end
    end
  end

  # Passwords of 16 bytes or fewer may be stored in either 16- or 20-byte
  # form (e.g. written by the web UI or bmc-config), so test both.  The
  # password is read at the prompt; see write_password.
  def self.password_matches?(_channel, id, password)
    check_prompt_secret(password)
    sizes = ['20']
    sizes = %w[16 20] if password.bytesize <= 16
    with_secret_file("#{password}\n") do |path|
      sizes.any? do |size|
        ipmitool_exec(['user', 'test', id.to_s, size], stdinfile: path, sensitive: true, failonfail: false).exitstatus.zero?
      end
    end
  end

  def self.write_priv(channel, id, priv)
    ipmitool_exec(['user', 'priv', id.to_s, priv.to_s, channel.to_s])
    ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=on', 'ipmi=on', 'link=on', "privilege=#{priv}"])
  end

  # @return [#call] enables the account with true and disables it with false
  def self.enabled_writer(id)
    ->(on) { ipmitool_exec(['user', on ? 'enable' : 'disable', id.to_s]) }
  end

  # Fails closed (see UserLogic.enable_failing_closed).
  def self.grant_access(channel, id, priv)
    set_priv = -> { ipmitool_exec(['user', 'priv', id.to_s, priv.to_s, channel.to_s]) }
    enable_failing_closed(id, set_priv: set_priv, set_enabled: enabled_writer(id)) do
      ipmitool_exec(['sol', 'payload', 'enable', channel.to_s, id.to_s])
      ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=on', 'ipmi=on', 'link=on', "privilege=#{priv}"])
    end
  end

  # Fails closed (see UserLogic.disable_failing_closed).  Channel, privilege
  # and SOL access are revoked on each channel before `user disable`,
  # because BMCs ignore or refuse permission changes on a disabled user.
  def self.revoke_access(channels, id, already_disabled: false)
    no_access = PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV.to_s
    revokes = channels.flat_map do |channel|
      [
        -> { ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=off', 'ipmi=off', 'link=off', "privilege=#{no_access}"]) },
        -> { ipmitool_exec(['user', 'priv', id.to_s, no_access, channel.to_s]) },
        -> { ipmitool_exec(['sol', 'payload', 'disable', channel.to_s, id.to_s]) },
      ]
    end
    disable_failing_closed(id, revokes: revokes, set_enabled: enabled_writer(id), already_disabled: already_disabled)
  end
end
