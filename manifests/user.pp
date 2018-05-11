# == Defined resource type: ipmi::user
#

define ipmi::user (
  String           $password,
  Integer[1,4]     $priv    = 4,
  Integer[1]       $user_id = 3,
  Optional[String] $user    = undef,
)
{
  include ipmi
  $_user = $user ? {
    undef   => $name,
    default => $user,
  }

  case $priv {
    1: {$privilege = 'CALLBACK'}
    2: {$privilege = 'USER'}
    3: {$privilege = 'OPERATOR'}
    4: {$privilege = 'ADMINISTRATOR'}
    default: {fail('invalid privilege level specified')}
  }

  exec { "ipmi_user_enable_${title}":
    command     => "/usr/bin/ipmitool user enable ${user_id}",
    refreshonly => true,
    require     => Package[$ipmi::packages],
  }

  exec { "ipmi_user_add_${title}":
    command => "/usr/bin/ipmitool user set name ${user_id} ${_user}",
    unless  => "/usr/bin/test \"$(ipmitool user list 1 | grep '^${user_id}' | awk '{print \$2}')\" = \"${_user}\"",
    notify  => [Exec["ipmi_user_priv_${title}"], Exec["ipmi_user_setpw_${title}"]],
    require => Package[$ipmi::packages],
  }

  exec { "ipmi_user_priv_${title}":
    command => "/usr/bin/ipmitool user priv ${user_id} ${priv} 1",
    unless  => "/usr/bin/test \"$(ipmitool user list 1 | grep '^${user_id}' | awk '{print \$6}')\" = ${privilege}",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
    require => Package[$ipmi::packages],
  }

  exec { "ipmi_user_setpw_${title}":
    command => "/usr/bin/ipmitool user set password ${user_id} \'${password}\'",
    unless  => "/usr/bin/ipmitool user test ${user_id} 16 \'${password}\'",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
    require => Package[$ipmi::packages],
  }

  exec { "ipmi_user_enable_sol_${title}":
    command     => "/usr/bin/ipmitool sol payload enable 1 ${user_id}",
    refreshonly => true,
    require     => Package[$ipmi::packages],
  }

  exec { "ipmi_user_channel_setaccess_${title}":
    command     => "/usr/bin/ipmitool channel setaccess 1 ${user_id} callin=on ipmi=on link=on privilege=${priv}",
    refreshonly => true,
    require     => Package[$ipmi::packages],
  }
}
