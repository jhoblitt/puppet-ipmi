# frozen_string_literal: true

Puppet::Type.newtype(:ipmi_snmp) do
  @doc = <<-DOC
    @summary
      Manages SNMP community string on a BMC LAN channel via IPMI.

    Supports both ipmitool and freeipmi backends.

    The lan channel is derived from the title when it is an integer.
    Otherwise it defaults to 1.

    @example Set SNMP community string on channel 1
      ipmi_snmp { '1':
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

  newparam(:lan_channel) do
    desc <<-DESC
      The IPMI LAN channel number to configure.
      Derived from the title when the title is an integer.
      Defaults to 1 when unset and not derivable from the title.
    DESC
    defaultto do
      title = resource[:name].to_s
      if title =~ %r{^\d+$}
        title.to_i
      else
        1
      end
    end
    validate do |value|
      raise Puppet::Error, 'lan_channel must be a positive integer' unless value.to_s =~ %r{^\d+$}
    end
    munge(&:to_i)
  end

  newparam(:ipmitool_cmd) do
    desc 'Path to the ipmitool binary.'
    defaultto '/usr/bin/ipmitool'
    validate do |value|
      raise Puppet::Error, 'ipmitool_cmd must be an absolute path' unless value.start_with?('/')
    end
  end

  newparam(:bmcconfig_cmd) do
    desc 'Path to the bmc-config binary (freeipmi).'
    defaultto '/usr/sbin/bmc-config'
    validate do |value|
      raise Puppet::Error, 'bmcconfig_cmd must be an absolute path' unless value.start_with?('/')
    end
  end

  newproperty(:community) do
    desc 'SNMP community string.'
    defaultto 'public'
  end
end
