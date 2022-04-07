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
#
define ipmi::network (
  Stdlib::IP::Address $ip      = '0.0.0.0',
  Stdlib::IP::Address $netmask = '255.255.255.0',
  Stdlib::IP::Address $gateway = '0.0.0.0',
  Enum['dhcp', 'static'] $type = 'dhcp',
  Integer $lan_channel         = 1,
) {
  require ipmi

  if $type == 'dhcp' {
    exec { "ipmi_set_dhcp_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipsrc dhcp",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 0",
    }
  } else {
    exec { "ipmi_set_static_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipsrc static",
      onlyif  => "/usr/bin/test $(ipmitool lan print ${lan_channel} | grep 'IP \
Address Source' | cut -f 2 -d : | grep -c DHCP) -eq 1",
      notify  => [
        Exec["ipmi_set_ipaddr_${lan_channel}"],
        Exec["ipmi_set_defgw_${lan_channel}"],
        Exec["ipmi_set_netmask_${lan_channel}"],
      ],
    }

    exec { "ipmi_set_ipaddr_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} ipaddr ${ip}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'IP Address  ' | sed -e 's/.* : //g')\" != \"${ip}\"",
    }

    exec { "ipmi_set_defgw_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} defgw ipaddr ${gateway}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'Default Gateway IP' | sed -e 's/.* : //g')\" != \"${gateway}\"",
    }

    exec { "ipmi_set_netmask_${lan_channel}":
      command => "/usr/bin/ipmitool lan set ${lan_channel} netmask ${netmask}",
      onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep \
'Subnet Mask' | sed -e 's/.* : //g')\" != \"${netmask}\"",
    }
  }
}
