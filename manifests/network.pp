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
# @param interface_type
#   Controls the NIC selection mode for the BMC.
#   Supported values: 'dedicated', 'shared', 'failover'.
#   Only applied when the manufacturer is known (Supermicro or Dell).
#   Leave undef to skip interface type configuration.
#
define ipmi::network (
  Stdlib::IP::Address                          $ip             = '0.0.0.0',
  Stdlib::IP::Address                          $netmask        = '255.255.255.0',
  Stdlib::IP::Address                          $gateway        = '0.0.0.0',
  Enum['dhcp', 'static']                       $type           = 'dhcp',
  Optional[Integer]                            $lan_channel    = undef,
  Optional[Enum['dedicated', 'shared', 'failover']] $interface_type = undef,
) {
  require ipmi::install

  $_real_lan_channel = $lan_channel ? {
    undef   => $ipmi::default_channel,
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

  if $interface_type != undef {
    $_manufacturer = $facts.dig('ipmitool_mc_info', 'Manufacturer Name')
    if $_manufacturer != undef {
      case $_manufacturer {
        'Supermicro': {
          $_raw_check = '0x30 0x70 0x0c'
          case $interface_type {
            'dedicated': { $_iface_code = 0 }
            'shared':    { $_iface_code = 1 }
            'failover':  { $_iface_code = 2 }
            default:     { $_iface_code = undef }
          }
          if $_iface_code != undef {
            # lint:ignore:140chars
            exec { "ipmi_set_interface_type_${_real_lan_channel}":
              command => "/usr/bin/ipmitool raw ${_raw_check} 1 ${_iface_code}",
              onlyif  => "/usr/bin/test $(/usr/bin/ipmitool raw ${_raw_check} 0) -ne ${_iface_code}",
            }
            # lint:endignore
          }
        }
        'Dell': {
          $_raw_set   = '0x30 0x24'
          $_raw_check = '0x30 0x25'
          case $interface_type {
            'dedicated': { $_iface_code = 2 }
            'shared':    { $_iface_code = 0 }
            'failover':  { $_iface_code = 1 }
            default:     { $_iface_code = undef }
          }
          if $_iface_code != undef {
            # lint:ignore:140chars
            exec { "ipmi_set_interface_type_${_real_lan_channel}":
              command => "/usr/bin/ipmitool raw ${_raw_set} ${_iface_code}",
              onlyif  => "/usr/bin/test $(/usr/bin/ipmitool raw ${_raw_check}) -ne ${_iface_code}",
            }
            # lint:endignore
          }
        }
        default: {
          # lint:ignore:140chars
          warning("${_manufacturer} does not have interface type behavior defined in this module.  Can you submit it?")
          # lint:endignore
        }
      }
    }
  }
}
