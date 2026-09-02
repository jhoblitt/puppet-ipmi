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
    undef   => $ipmi::default_channel,
    default => $lan_channel,
  }

  if $type == 'dhcp' {
    ipmi_network { "ipmi_network_${title}":
      lan_channel => $_real_lan_channel,
      type        => 'dhcp',
    }
  } else {
    ipmi_network { "ipmi_network_${title}":
      lan_channel => $_real_lan_channel,
      type        => 'static',
      ip          => $ip,
      netmask     => $netmask,
      gateway     => $gateway,
    }
  }
}
