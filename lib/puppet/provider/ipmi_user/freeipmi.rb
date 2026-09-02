# frozen_string_literal: true

require 'puppet'
require File.join(File.dirname(__FILE__), '..', 'ipmi')

Puppet::Type.type(:ipmi_user).provide(
  :freeipmi,
  parent: Puppet::Provider::Ipmi
) do
  desc 'Manage BMC user accounts via freeipmi (bmc-config)'

  confine commands: { bmcconfig: 'bmc-config' }

  # ---------------------------------------------------------------------------
  # Helper methods
  # ---------------------------------------------------------------------------

  def bmcconfig_cmd
    @resource[:bmcconfig_cmd] || '/usr/sbin/bmc-config'
  end

  def bmcconfig_exec(args, failonfail: false)
    Puppet::Util::Execution.execute("#{bmcconfig_cmd} #{args}", failonfail: failonfail)
  end

  def freeipmi_priv_map
    { 4 => 'Administrator', 3 => 'Operator', 2 => 'User', 1 => 'Callback' }
  end

  def channel
    @resource[:channel]
  end

  def resolved_user_id
    return @resolved_user_id if defined?(@resolved_user_id)

    requested = @resource[:user_id]
    @resolved_user_id = if requested == :auto
                          resolve_auto_user_id(user_name, list_all_users)
                        else
                          requested
                        end
  end

  def user_name
    @resource[:user]
  end

  # Build a list of all BMC user slots from a single bmc-config checkout.
  def list_all_users
    return @list_all_users if defined?(@list_all_users)

    output = bmcconfig_exec('--checkout 2>/dev/null')
    return @list_all_users = [] if output.nil? || output.empty?

    section_ids = []
    names = {}
    current_id = nil
    output.each_line do |line|
      if line =~ %r{^\s*Section\s+User(\d+)}i
        current_id = Regexp.last_match(1).to_i
        section_ids << current_id
      elsif current_id && line =~ %r{^\s*Username\s+(.+)$}
        name = Regexp.last_match(1).strip
        name = '' if ['<username-not-set-yet>', 'NULL'].include?(name)
        names[current_id] = name
        current_id = nil
      end
    end

    @list_all_users = section_ids.sort.map do |id|
      { id: id, name: names.fetch(id, '') }
    end
  end

  def max_user_slot
    (list_all_users.map { |u| u[:id] }.max || 15)
  end

  def real_password
    pw = @resource[:password]
    return nil if pw.nil?

    pw.is_a?(Puppet::Pops::Types::PSensitiveType::Sensitive) ? pw.unwrap : pw.to_s
  end

  def user_section
    "User#{resolved_user_id}"
  end

  # ---------------------------------------------------------------------------
  # Purge ID mismatch
  # ---------------------------------------------------------------------------

  # Scan all BMC user slots and disable any slot that holds the target
  # username at an ID other than resolved_user_id.
  def purge_mismatched_ids!
    return unless [:true, true].include?(@resource[:purge_id_mismatch])
    return unless [:true, true].include?(@resource[:enable])

    (1..max_user_slot).each do |slot|
      next if slot == resolved_user_id

      slot_section = "User#{slot}"
      slot_username = bmc_config_get(slot_section, 'Username')
      next if slot_username.nil?
      next unless slot_username == user_name
      next if slot_username =~ %r{^DISABLED_}

      Puppet.debug("ipmi_user: purging #{user_name} from slot #{slot} (expected at #{resolved_user_id})")
      bmc_config_set(slot_section, 'Username', "DISABLED_#{slot}")
      bmc_config_set(slot_section, 'Enable_User', 'No')
      bmc_config_set(slot_section, "Lan_Channel_Channel_#{channel}_Privilege_Limit", 'No_Access')
      bmc_config_set(slot_section, "Lan_Channel_Channel_#{channel}_IPMI_Messaging", 'No')
      bmc_config_set(slot_section, "Lan_Channel_Channel_#{channel}_Link_Authentication", 'No')
      bmc_config_set(slot_section, "SOL_Payload_Channel_#{channel}", 'No')
    end
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

  def enable
    val = bmc_config_get(user_section, 'Enable_User')
    return :false if val.nil?

    val =~ %r{^Yes$}i ? :true : :false
  end

  def enable=(val)
    purge_mismatched_ids!

    if [:true, true].include?(val)
      enable_user!
    else
      disable_user!
    end
  end

  def priv
    val = bmc_config_get(user_section, "Lan_Channel_Channel_#{channel}_Privilege_Limit")
    return nil if val.nil?

    freeipmi_priv_map.key(val) || 0
  end

  def priv=(val)
    priv_name = freeipmi_priv_map[val] || 'Administrator'
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_Privilege_Limit", priv_name)
  end

  private

  def enable_user!
    # Set username
    bmc_config_set(user_section, 'Username', user_name)

    # Set password
    pw = real_password
    bmc_config_set(user_section, 'Password', pw) if pw && !pw.empty?

    # Enable user
    bmc_config_set(user_section, 'Enable_User', 'Yes')

    # Set privilege
    priv_level = @resource[:priv] || 4
    priv_name = freeipmi_priv_map[priv_level] || 'Administrator'
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_Privilege_Limit", priv_name)

    # Enable IPMI messaging
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_IPMI_Messaging", 'Yes')

    # Enable link auth
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_Link_Authentication", 'Yes')

    # Enable SOL payload
    bmc_config_set(user_section, "SOL_Payload_Channel_#{channel}", 'Yes')
  end

  def disable_user!
    # Disable user
    bmc_config_set(user_section, 'Enable_User', 'No')

    # Set privilege to No Access
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_Privilege_Limit", 'No_Access')

    # Disable IPMI messaging
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_IPMI_Messaging", 'No')

    # Disable link auth
    bmc_config_set(user_section, "Lan_Channel_Channel_#{channel}_Link_Authentication", 'No')

    # Disable SOL payload
    bmc_config_set(user_section, "SOL_Payload_Channel_#{channel}", 'No')
  end
end
