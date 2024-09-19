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
# === Fact Format
#
#     ipmi1_ipaddress = 192.168.101.1
#     ipmi1_subnet_mask = 255.255.255.0
#     ...
#
# where the 1 in "ipmi1" corresponds to the ID of the BMC according to
# ipmitool lan print.
#
# Additionally for compatibility with The Foreman, the first IPMI
# interface (i.e. the one from ipmi lan print 1) gets all facts
# repeated as just ipmi_foo:
#
#     ipmi_ipaddress = 192.168.101.1
#     ipmi_subnet_mask = 255.255.255.0
#     ...
#
class IPMIChannel
  def initialize(channel_nr)
    @channel_nr = channel_nr
  end

  def load_facts
    return unless Facter::Util::Resolution.which('ipmitool')

    ipmitool_output = Facter::Util::Resolution.exec("ipmitool lan print #{@channel_nr} 2>&1")
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

  def add_ipmi_fact(name, value)
    fact_names = []
    fact_names.push("ipmi_#{name}") unless fact_names.include?("ipmi_#{name}")
    fact_names.push("ipmi#{@channel_nr}_#{name}")
    fact_names.each do |n|
      Facter.add(n) do
        confine kernel: 'Linux'
        setcode do
          value
        end
      end
    end
    @has_facts = true
  end
end

channels = (1..11).to_a
channels.each do |channel|
  @channel_nr = channel
  IPMIChannel.new(@channel_nr).load_facts
end

Facter.add(:ipmi) do
  confine kernel: 'Linux'
  setcode do
    ipmi = {}
    if Facter::Util::Resolution.which('ipmitool')
      (1..11).each do |channel_nr|
        lan_channel = {}
        ipmitool_output = Facter::Util::Resolution.exec("ipmitool lan print #{channel_nr} 2>&1")
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
        ipmitool_user_output = Facter::Util::Resolution.exec("ipmitool user list #{channel_nr} 2>&1")
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
