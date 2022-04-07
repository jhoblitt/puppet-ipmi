#
# @summary Manage BMC users
#
# @param user
#   Controls the username of the user to be created.
# @param password
#   Controls the password of the user to be created.
# @param priv
#   Possible values:
#   `4` - ADMINISTRATOR,
#   `3` - OPERATOR,
#   `2` - USER,
#   `1` - CALLBACK
#
#   Controls the rights of the user to be created.
# @param user_id
#   The user id of the user to be created. Should be unique from existing users. On
#   SuperMicro IPMI, user id 2 is reserved for the ADMIN user.
#
define ipmi::user (
  String $password,
  String $user     = 'root',
  Integer $priv    = 4,
  Integer $user_id = 3,
) {
  require ipmi

  case $priv {
    1: { $privilege = 'CALLBACK' }
    2: { $privilege = 'USER' }
    3: { $privilege = 'OPERATOR' }
    4: { $privilege = 'ADMINISTRATOR' }
    default: { fail('invalid privilege level specified') }
  }

  exec { "ipmi_user_enable_${title}":
    command     => "/usr/bin/ipmitool user enable ${user_id}",
    refreshonly => true,
  }

  exec { "ipmi_user_add_${title}":
    command => "/usr/bin/ipmitool user set name ${user_id} ${user}",
    unless  => "/usr/bin/test \"$(ipmitool user list 1 | grep '^${user_id}' | awk '{print \$2}' | head -n1)\" = \"${user}\"",
    notify  => [Exec["ipmi_user_priv_${title}"], Exec["ipmi_user_setpw_${title}"]],
  }

  exec { "ipmi_user_priv_${title}":
    command => "/usr/bin/ipmitool user priv ${user_id} ${priv} 1",
    unless  => "/usr/bin/test \"$(ipmitool user list 1 | grep '^${user_id}' | awk '{print \$6}' | head -n1)\" = ${privilege}",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
  }

  exec { "ipmi_user_setpw_${title}":
    command => "/usr/bin/ipmitool user set password ${user_id} \'${password}\'",
    unless  => "/usr/bin/ipmitool user test ${user_id} 16 \'${password}\'",
    notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
  }

  exec { "ipmi_user_enable_sol_${title}":
    command     => "/usr/bin/ipmitool sol payload enable 1 ${user_id}",
    refreshonly => true,
  }

  exec { "ipmi_user_channel_setaccess_${title}":
    command     => "/usr/bin/ipmitool channel setaccess 1 ${user_id} callin=on ipmi=on link=on privilege=${priv}",
    refreshonly => true,
  }
}
