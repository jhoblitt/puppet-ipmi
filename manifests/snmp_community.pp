# @summary
#
# @param lan_channel the ipmi lan channle to configure
# @param community optional community to use if not present us $name
# @param 
#   random if true use a random comunity string, use 
#   the community as a seed

define ipmi::snmp_community (
  Integer           $lan_channel = 1,
  Optional[String]  $community   = undef,
  Optional[Boolean] $random      = false,
) {
  include ipmi
  $_community_or_seed = $community ? {
    undef   => $name,
    default => $community,
  }
  $_community = $random ? {
    true    => fqdn_rand_string(16, '', $_community_or_seed),
    default => $_community_or_seed,
  }
  exec { "ipmi_set_snmp_${lan_channel}":
    command => "/usr/bin/ipmitool lan set ${lan_channel} snmp ${_community}",
    onlyif  => "/usr/bin/test \"$(ipmitool lan print ${lan_channel} |\
    grep 'SNMP Community String' | sed -e 's/.* : //g')\" != \"${_community}\"",
    require => Package[$ipmi::packages],
  }
}
