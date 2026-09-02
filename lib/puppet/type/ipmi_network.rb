# frozen_string_literal: true

Puppet::Type.newtype(:ipmi_network) do
  @doc = <<-DOC
    @summary
      Manages BMC network configuration via IPMI.

    Supports both ipmitool and freeipmi backends.  Each property is
    independently managed - leave a property unset to skip management
    of that setting.

    The lan channel is derived from the title when it is an integer.
    Otherwise it defaults to 1.

    @example Configure DHCP on channel 1
      ipmi_network { '1':
        type => 'dhcp',
      }

    @example Configure static IP on channel 2
      ipmi_network { 'bmc_network':
        lan_channel => 2,
        type        => 'static',
        ip          => '192.168.1.100',
        netmask     => '255.255.255.0',
        gateway     => '192.168.1.1',
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

  newproperty(:type) do
    desc 'IP address source: dhcp or static.'
    newvalues(:dhcp, :static)
  end

  newproperty(:ip) do
    desc 'IP address for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid IP address: #{value}" unless value =~ %r{^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$}
    end
  end

  newproperty(:netmask) do
    desc 'Subnet mask for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid netmask: #{value}" unless value =~ %r{^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$}
    end
  end

  newproperty(:gateway) do
    desc 'Default gateway for the BMC (only used when type is static).'
    validate do |value|
      raise Puppet::Error, "Invalid gateway: #{value}" unless value =~ %r{^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$}
    end
  end
end
