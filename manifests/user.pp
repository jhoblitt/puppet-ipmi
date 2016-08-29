# == Defined resource type: ipmi::user
#

define ipmi::user (
  $password,
  $user = 'root',
  $priv = 4,
  $user_id = 3,
  $lan_channel = $::ipmi_lan_channel,
)
{
  require ::ipmi

  validate_string($password,$user)
  validate_integer($priv)
  validate_integer($user_id)

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
  }

  exec { "ipmi_user_add_${title}":
    command => "/usr/bin/ipmitool user set name ${user_id} ${user}",
    unless  => "/usr/bin/test \"$(ipmitool user list ${lan_channel} | grep '^${user_id}' | awk '{print \$2}')\" = \"${user}\"",
    notify  => [Exec["ipmi_user_priv_${title}"], Exec["ipmi_user_setpw_${title}"]],
  }

  exec { "ipmi_user_priv_${title}":
    command => "/usr/bin/ipmitool user priv ${user_id} ${priv} ${lan_channel}",
    unless  => "/usr/bin/test \"$(ipmitool user list ${lan_channel} | grep '^${user_id}' | awk '{print \$6}')\" = ${privilege}",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
  }

  exec { "ipmi_user_setpw_${title}":
    command => "/usr/bin/ipmitool user set password ${user_id} \'${password}\'",
    unless  => "/usr/bin/ipmitool user test ${user_id} 16 \'${password}\'",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
  }

  exec { "ipmi_user_enable_sol_${title}":
    command     => "/usr/bin/ipmitool sol payload enable ${lan_channel} ${user_id}",
    refreshonly => true,
  }

  exec { "ipmi_user_channel_setaccess_${title}":
    command     => "/usr/bin/ipmitool channel setaccess ${lan_channel} ${user_id} callin=on ipmi=on link=on privilege=${priv}",
    refreshonly => true,
  }
}
