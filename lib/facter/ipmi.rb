#!/usr/bin/env ruby
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
  public
  def initialize channel_nr
    @channel_nr = channel_nr
  end

  def load_facts
    if Facter::Util::Resolution.which('ipmitool')
      ipmitool_output = Facter::Util::Resolution.exec("ipmitool lan print #{@channel_nr} 2>&1")
      parse_ipmitool_output ipmitool_output
    end
  end

  private
  def parse_ipmitool_output ipmitool_output
    ipmitool_output.each_line do |line|
      case line.strip
      when /^IP Address\s*:\s+(\S.*)/
        add_ipmi_fact("ipaddress", $1)
      when /^IP Address Source\s*:\s+(\S.*)/
        add_ipmi_fact("ipaddress_source", $1)
      when /^Subnet Mask\s*:\s+(\S.*)/
        add_ipmi_fact("subnet_mask", $1)
      when /^MAC Address\s*:\s+(\S.*)/
        add_ipmi_fact("macaddress", $1)
      when /^Default Gateway IP\s*:\s+(\S.*)/
        add_ipmi_fact("gateway", $1)
      end
    end
  end

  def add_ipmi_fact name, value
    fact_names = []
    if @channel_nr == 1 then fact_names.push("ipmi_#{name}") end
    fact_names.push("ipmi#{@channel_nr}_#{name}")
    fact_names.each do |name|
      Facter.add(name) do
        confine :kernel => "Linux"
        setcode do
          value
        end
      end
    end
    @has_facts = true
  end
end

channel_array = (1..11).to_a
channel_array.each do | channel |
  @channel_nr = channel
  IPMIChannel.new(@channel_nr).load_facts
end
