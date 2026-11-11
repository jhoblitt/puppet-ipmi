#!/usr/bin/env ruby
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

# Flat facts are exported as channel-agnostic keys (e.g. ipmi_ipaddress)
# for The Foreman. The deprecated per-channel ipmi<N>_<fact> keys were
# removed; use the structured `ipmi` fact or these flat keys instead.

class IPMIChannel
  # Creates a new IPMIChannel for the given channel number.
  # @param channel_nr [Integer] The IPMI LAN channel number to query.
  def initialize(channel_nr)
    @channel_nr = channel_nr
  end

  # Queries ipmitool for LAN information on this channel and registers Facter facts.
  def load_facts
    return unless Facter::Core::Execution.which('ipmitool')

    ipmitool_output = Facter::Core::Execution.execute("ipmitool lan print #{@channel_nr} 2>&1", on_fail: '')
    parse_ipmitool_output ipmitool_output
  end

  private

  def parse_ipmitool_output(ipmitool_output)
    ipmitool_output.each_line do |line|
      case line.strip
      when %r{^IP Address\s*:\s+(\S.*)}
        add_ipmi_fact('ipaddress', Regexp.last_match(1))
        add_ipmi_fact('lan_channel', @channel_nr)
      when %r{^IP Address Source\s*:\s+(\S.*)}
        add_ipmi_fact('ipaddress_source', Regexp.last_match(1))
      when %r{^Subnet Mask\s*:\s+(\S.*)}
        add_ipmi_fact('subnet_mask', Regexp.last_match(1))
      when %r{^MAC Address\s*:\s+(\S.*)}
        add_ipmi_fact('macaddress', Regexp.last_match(1))
      when %r{^Default Gateway IP\s*:\s+(\S.*)}
        add_ipmi_fact('gateway', Regexp.last_match(1))
      end
    end
  end

  # Registers the channel-agnostic flat facts (e.g. ipmi_ipaddress) used
  # for The Foreman compatibility.
  def add_ipmi_fact(name, value)
    Facter.add("ipmi_#{name}") do
      confine kernel: 'Linux'
      setcode do
        value
      end
    end
  end
end

channels = (1..11).to_a
channels.each do |channel|
  IPMIChannel.new(channel).load_facts
end

Facter.add(:ipmi) do
  confine kernel: 'Linux'
  setcode do
    ipmi = {}
    if Facter::Core::Execution.which('ipmitool')
      (1..11).each do |channel_nr|
        lan_channel = {}
        ipmitool_output = Facter::Core::Execution.execute("ipmitool lan print #{channel_nr} 2>&1", on_fail: '')
        ipmitool_output.each_line do |line|
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

        lan_channel['channel'] = channel_nr

        # Get Users
        ipmitool_user_output = Facter::Core::Execution.execute("ipmitool user list #{channel_nr} 2>&1", on_fail: '')
        lan_channel['users'] = {}
        ipmitool_user_output.each_line do |line|
          case line.strip
          when %r{^(\d+)\s+(.+)(\s+(true|false)\s+){3}(USER|ADMINISTRATOR|CALLBACK|OPERATOR|NO ACCESS)$}
            id = Regexp.last_match(1).strip.to_i
            name = Regexp.last_match(2).strip
            privilege = Regexp.last_match(5).strip
            lan_channel['users'][id] = {
              id: id,
              name: name,
              privilege: privilege,
            }
          end
        end

        ipmi['default'] = lan_channel unless ipmi.key?('default')
        ipmi[channel_nr] = lan_channel
      end
    end
    ipmi
  end
end
