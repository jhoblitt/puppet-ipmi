# frozen_string_literal: true

#
# IPMI facts, in a format compatible with The Foreman
#
# Sending these facts to a puppetmaster equipped with RedHat's Foreman
# will cause the latter to create the BMC interfaces the next time the
# Puppet agent runs. One then only has to manually add the access
# credentials, and presto, you can run basic IPMI actions (e.g. reboot
# to PXE) from The Foreman's web UI.
#

# The structured `:ipmi` fact gathers every configured LAN channel with a
# single `ipmitool` invocation per channel. The channel-agnostic flat facts
# below (used by The Foreman) reuse that same result through `Facter.value`,
# so `ipmitool` is run once per channel per Facter run instead of once per
# flat fact.

Facter.add(:ipmi) do
  confine kernel: 'Linux'

  setcode do
    next {} unless Facter::Core::Execution.which('ipmitool')

    ipmi = {}

    # IPMI LAN channels are 1..11. Channels that are not configured return
    # an empty result; probing the whole range is the predictable, BMC-safe
    # behaviour and avoids hanging the agent run on a wedged BMC.
    (1..11).each do |channel_nr|
      output = Facter::Core::Execution.execute("ipmitool lan print #{channel_nr} 2>&1", on_fail: '')

      lan_channel = {}
      output.each_line do |line|
        case line.strip
        when %r{^IP Address\s*:\s+(\S.*)}
          lan_channel['ipaddress'] = Regexp.last_match(1)
        when %r{^IP Address Source\s*:\s+(\S.*)}
          lan_channel['ipaddress_source'] = Regexp.last_match(1)
        when %r{^Subnet Mask\s*:\s+(\S.*)}
          lan_channel['subnet_mask'] = Regexp.last_match(1)
        when %r{^MAC Address\s*:\s+(\S.*)}
          lan_channel['macaddress'] = Regexp.last_match(1)
        when %r{^Default Gateway IP\s*:\s+(\S.*)}
          lan_channel['gateway'] = Regexp.last_match(1)
        end
      end

      next if lan_channel.empty?

      # Only channels that expose a LAN are queried for users, halving the
      # `user list` round-trips on hosts whose other channels are empty.
      lan_channel['users'] = {}
      ipmitool_user_output = Facter::Core::Execution.execute("ipmitool user list #{channel_nr} 2>&1", on_fail: '')
      ipmitool_user_output.each_line do |line|
        case line.strip
        when %r{^(\d+)\s+(.+)(\s+(true|false)\s+){3}(USER|ADMINISTRATOR|CALLBACK|OPERATOR|NO ACCESS)$}
          id = Regexp.last_match(1).strip.to_i
          lan_channel['users'][id] = {
            id: id,
            name: Regexp.last_match(2).strip,
            privilege: Regexp.last_match(5).strip,
          }
        end
      end

      lan_channel['channel'] = channel_nr
      ipmi[channel_nr] = lan_channel
      ipmi['default'] = lan_channel unless ipmi.key?('default')
    end

    ipmi
  end
end

# Channel-agnostic flat facts used by The Foreman. Each one is derived from
# the aggregate `:ipmi` fact, so no extra `ipmitool` invocation is needed.
%i[
  ipaddress
  ipaddress_source
  subnet_mask
  macaddress
  gateway
].each do |field|
  Facter.add("ipmi_#{field}") do
    confine kernel: 'Linux'

    setcode do
      data = Facter.value(:ipmi)
      data['default'][field.to_s] if data && data['default']
    end
  end
end
