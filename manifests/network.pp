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
# @param interface_type
#   Controls the IPMI failover settings
#   NOTE: each BMC vendor has their own method for doing this.
#         If your vendor is not listed here, it will do nothing.
#   Known vendors: Supermicro, Dell
#
define ipmi::network (
  Stdlib::IP::Address $ip      = '0.0.0.0',
  Stdlib::IP::Address $netmask = '255.255.255.0',
  Stdlib::IP::Address $gateway = '0.0.0.0',
  Enum['dhcp', 'static'] $type = 'dhcp',
  Integer $lan_channel         = 1,
  Optional[Enum['dedicated', 'shared', 'failover']] $interface_type = undef,
) {
  require ipmi

  if defined($interface_type) {
    if 'Manufacturer Name' in $facts['ipmitool_mc_info'] {
      case $facts['ipmitool_mc_info']['Manufacturer Name'] {
        'Supermicro': {
          $interface_type_raw_command_code = '0x30 0x70 0x0c'
          case $interface_type {
            'dedicated': {
              $interface_code = 0
            }
            'shared': {
              $interface_code = 1
            }
            'failover': {
              $interface_code = 2
            }
            default: {
              $interface_code = undef
            }
          }
          # lint:ignore:140chars
          exec { "ipmi_set_interface_type_${lan_channel}":
            command => "/usr/bin/ipmitool raw ${interface_type_raw_command_code} 1 ${interface_code}",
            onlyif  => "/usr/bin/test $(/usr/bin/ipmitool raw ${interface_type_raw_command_code} 0) -ne ${interface_code}",
          }
          # lint:endignore
        }
        'Dell': {
          $interface_type_raw_set_code = '0x30 0x24'
          $interface_type_raw_check_code = '0x30 0x25'
          case $interface_type {
            'dedicated': {
              $interface_code = 2
            }
            'shared': {
              $interface_code = 0
            }
            'failover': {
              $interface_code = 1
            }
            default: {
              $interface_code = undef
            }
          }
          # lint:ignore:140chars
          exec { "ipmi_set_interface_type_${lan_channel}":
            command => "/usr/bin/ipmitool raw ${interface_type_raw_set_code} ${interface_code}",
            onlyif  => "/usr/bin/test $(/usr/bin/ipmitool raw ${interface_type_raw_check_code}) -ne ${interface_code}",
          }
          # lint:endignore
        }
        default: {
          # lint:ignore:140chars
          warning("${facts['ipmitool_mc_info']['Manufacturer Name']} does not have interface type behavior defined in this module.  Can you submit it?")
          # lint:endignore
        }
      }
    }
  }

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
