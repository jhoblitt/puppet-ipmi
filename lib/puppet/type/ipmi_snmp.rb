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
    desc <<-DESC
      SNMP community string. Defaults to public and actively replaces any existing BMC community.

      At most 18 bytes, the size of the BMC's community field; a multibyte
      character counts as each of its bytes.  It must not start or end with
      whitespace: both backends read the community back with that stripped,
      so it would never be in sync.

      Always sensitive: Puppet reports a change as
      `changed [redacted] to [redacted]`.  `Sensitive()` is accepted but not
      required.

      The community is never put on a command line.  With ipmitool it must
      not contain `#`, whitespace other than a space, a NUL byte, both kinds
      of quote, or `~` together with a space or quote, and must not start
      with `help`, which ipmitool takes as a request for help.  With freeipmi
      it must not contain whitespace or a NUL byte.
    DESC
    defaultto 'public'
    sensitive true
    validate do |value|
      str = value.to_s
      raise Puppet::Error, 'community must be a non-empty string' if str.empty?
      raise Puppet::Error, 'community must be 18 bytes or fewer' if str.bytesize > 18
      raise Puppet::Error, 'community must not start or end with whitespace, which is lost when it is read back' if str.match?(%r{\A\s|\s\z})
    end
  end
end
