#
# @summary Manage SNMP community strings
#
# @param snmp
#   Controls the snmp string of the IPMI network interface.
# @param lan_channel
#   Controls the lan channel of the IPMI network on which snmp is to be configured.
#   Defaults to the first detected lan channel, starting at 1 ending at 11
#
define ipmi::snmp (
  String $snmp                   = 'public',
  Optional[Integer] $lan_channel = undef,
) {
  require ipmi::install

  $_real_lan_channel = $lan_channel ? {
    undef => $ipmi::default_channel,
    default => $lan_channel,
  }

  exec { "ipmi_set_snmp_${_real_lan_channel}":
    command => "/usr/bin/ipmitool lan set ${_real_lan_channel} snmp ${snmp}",
    onlyif  => "/usr/bin/test \"$(ipmitool lan print ${_real_lan_channel} | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"${snmp}\"",
  }
}
