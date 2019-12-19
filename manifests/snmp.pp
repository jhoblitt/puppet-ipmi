# == Defined resource type: ipmi::snmp
#

define ipmi::snmp (
  $snmp = 'public',
  $lan_channel = $::ipmi_lan_channel,
)
{
  require ::ipmi

  validate_string($snmp)
  validate_integer($lan_channel)

  exec { "ipmi_set_snmp_${lan_channel}":
    command => "/usr/bin/ipmitool lan set ${lan_channel} snmp ${snmp}",
    onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} | grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"${snmp}\"",
  }
}
