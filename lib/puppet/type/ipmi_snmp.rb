# frozen_string_literal: true

require 'puppet_x/ipmi/lan_channel'

Puppet::Type.newtype(:ipmi_snmp) do
  include PuppetX::Ipmi::LanChannel

  @doc = <<-DOC
    @summary
      Manages SNMP community string on a BMC LAN channel via IPMI.

    Supports both ipmitool and freeipmi backends. Omitting `community`
    actively sets the BMC community to `public`; it does not leave the
    existing credential unchanged. Set it explicitly to avoid surprises.

    The lan channel is derived from the title when it is an integer.
    Otherwise it defaults to 1 when declared directly. The ipmi class can
    inject the node's ipmi.default.channel fact or ipmi::default_channel.

    Two resources may not target the same LAN channel; doing so will fail
    the pre-run check instead of fighting on every run.

    @example Set SNMP community string on channel 1
      ipmi_snmp { 'snmp1':
        community => 'public',
      }

    @example Set SNMP community string on channel 2
      ipmi_snmp { 'bmc_snmp':
        lan_channel => 2,
        community   => 'secret',
      }
  DOC

  newparam(:name, namevar: true) do
    desc 'Resource title. When it is an integer, the lan channel is derived automatically.'
  end

  newproperty(:community) do
    desc 'SNMP community string. Defaults to public and actively replaces any existing BMC community.'
    defaultto 'public'
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'community must be a non-empty string' if str.empty?
      raise Puppet::Error, 'community must be 18 characters or fewer' if str.length > 18
    end
  end
end
