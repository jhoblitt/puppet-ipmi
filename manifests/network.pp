# @summary Manage BMC network configuration
#
# @param ip
#   Controls the IP of the IPMI network.
# @param netmask
#   Controls the subnet mask of the IPMI network.
# @param gateway
#   Controls the gateway of the IPMI network.
# @param type
#   Controls the if IP will be from DHCP or Static.
# @param lan_channel
#   Controls the lan channel of the IPMI network to be configured.
#   Defaults to the first detected lan channel, starting at 1 ending at 11
#
define ipmi::network (
  Stdlib::IP::Address $ip        = '0.0.0.0',
  Stdlib::IP::Address $netmask   = '255.255.255.0',
  Stdlib::IP::Address $gateway   = '0.0.0.0',
  Enum['dhcp', 'static'] $type   = 'dhcp',
  Optional[Integer] $lan_channel = undef
) {
  require ipmi::install

  $_real_lan_channel = $lan_channel ? {
    undef => $ipmi::default_channel,
    default => $lan_channel,
  }

  if $type == 'dhcp' {
    exec { "ipmi_set_dhcp_${_real_lan_channel}":
      command => "/usr/bin/ipmitool lan set ${_real_lan_channel} ipsrc dhcp",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${_real_lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 0",
    }
  } else {
    exec { "ipmi_set_static_${_real_lan_channel}":
      command => "/usr/bin/ipmitool lan set ${_real_lan_channel} ipsrc static",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${_real_lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 1",
      notify  => [
        Exec["ipmi_set_ipaddr_${_real_lan_channel}"],
        Exec["ipmi_set_defgw_${_real_lan_channel}"],
        Exec["ipmi_set_netmask_${_real_lan_channel}"],
      ],
    }

    exec { "ipmi_set_ipaddr_${_real_lan_channel}":
      command => "/usr/bin/ipmitool lan set ${_real_lan_channel} ipaddr ${ip}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${_real_lan_channel} | grep \
'IP Address  ' | sed -e 's/.* : //g')\" != \"${ip}\"",
    }

    exec { "ipmi_set_defgw_${_real_lan_channel}":
      command => "/usr/bin/ipmitool lan set ${_real_lan_channel} defgw ipaddr ${gateway}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${_real_lan_channel} | grep \
'Default Gateway IP' | sed -e 's/.* : //g')\" != \"${gateway}\"",
    }

    exec { "ipmi_set_netmask_${_real_lan_channel}":
      command => "/usr/bin/ipmitool lan set ${_real_lan_channel} netmask ${netmask}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${_real_lan_channel} | grep \
'Subnet Mask' | sed -e 's/.* : //g')\" != \"${netmask}\"",
    }
  }
}
