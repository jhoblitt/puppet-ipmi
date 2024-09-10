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
  String $snmp         = 'public',
  Integer $lan_channel = $facts['ipmi_lan_channel'],
) {
  require ipmi::install

  exec { "ipmi_set_snmp_${lan_channel}":
    command => "/usr/bin/ipmitool lan set ${lan_channel} snmp ${snmp}",
    onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"${snmp}\"",
  }
}
