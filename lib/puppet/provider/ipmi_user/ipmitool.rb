# frozen_string_literal: true

require 'puppet'
require 'puppet_x/ipmi/provider/ipmitool'
require 'puppet_x/ipmi/provider/user_logic'

Puppet::Type.type(:ipmi_user).provide(
  :ipmitool,
  parent: PuppetX::Ipmi::Provider::Ipmitool
) do
  desc 'Manage BMC user accounts via ipmitool'

  commands ipmitool: 'ipmitool'
  defaultfor kernel: 'Linux'

  include PuppetX::Ipmi::Provider::UserLogic

  # @return [Hash<Integer, String>] mapping of privilege numbers to ipmitool names
  def self.privilege_names
    { 4 => 'ADMINISTRATOR', 3 => 'OPERATOR', 2 => 'USER', 1 => 'CALLBACK', 15 => 'NO ACCESS' }
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
        priv: privilege_names.key(Regexp.last_match(6).strip) || 0,
      }
    end
    users
  end

  # `user list` has no enable column; Get User Access reports it, so it is
  # queried only for slots that could be enabled.
  def self.read_users(channel)
    users = parse_user_list(ipmitool_exec(['user', 'list', channel.to_s]))
    users.each do |entry|
      entry[:enabled] = false
      next if entry[:name].empty? || entry[:priv] == PuppetX::Ipmi::Provider::UserLogic::NO_ACCESS_PRIV

      access = parse_colon_kv(ipmitool_exec(['channel', 'getaccess', channel.to_s, entry[:id].to_s]))
      entry[:enabled] = access.fetch('Enable Status', 'disabled') == 'enabled'
    end
    users
  end

  def self.write_name(_channel, id, name)
    ipmitool_exec(['user', 'set', 'name', id.to_s, name.to_s])
  end

  # Passwords of 16 bytes or fewer use the 16 byte form.
  def self.write_password(_channel, id, password)
    capacity = '20'
    capacity = '16' if password.bytesize <= 16
    ipmitool_exec(['user', 'set', 'password', id.to_s, password, capacity], sensitive: true)
  end

  # Passwords of 16 bytes or fewer may be stored in either 16- or 20-byte
  # form (e.g. written by the web UI or bmc-config), so test both.
  def self.password_matches?(_channel, id, password)
    sizes = ['20']
    sizes = %w[16 20] if password.bytesize <= 16
    sizes.any? do |size|
      ipmitool_exec(['user', 'test', id.to_s, size, password], sensitive: true, failonfail: false).exitstatus.zero?
    end
  end

  def self.write_priv(channel, id, priv)
    ipmitool_exec(['user', 'priv', id.to_s, priv.to_s, channel.to_s])
    ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=on', 'ipmi=on', 'link=on', "privilege=#{priv}"])
  end

  def self.write_access(channel, id, enabled, priv)
    if enabled
      ipmitool_exec(['user', 'priv', id.to_s, priv.to_s, channel.to_s])
      ipmitool_exec(['user', 'enable', id.to_s])
      ipmitool_exec(['sol', 'payload', 'enable', channel.to_s, id.to_s])
      ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=on', 'ipmi=on', 'link=on', "privilege=#{priv}"])
    else
      # Remove channel access before disabling; some BMCs ignore setaccess on
      # disabled users.
      ipmitool_exec(['channel', 'setaccess', channel.to_s, id.to_s, 'callin=off', 'ipmi=off', 'link=off', "privilege=#{priv}"])
      ipmitool_exec(['user', 'priv', id.to_s, priv.to_s, channel.to_s])
      ipmitool_exec(['user', 'disable', id.to_s])
      ipmitool_exec(['sol', 'payload', 'disable', channel.to_s, id.to_s])
    end
  end
end
