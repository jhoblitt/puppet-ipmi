#
# @summary Manage BMC users
#
# @param user
#   Controls the username of the user to be created.
# @param priv
#   Possible values:
#   `4` - ADMINISTRATOR,
#   `3` - OPERATOR,
#   `2` - USER,
#   `1` - CALLBACK
#
#   Controls the rights of the user to be created.
# @param enable
#   Should this user be enabled?
# @param user_id
#   The user id of the user to be created. Should be unique from existing users.
#   On SuperMicro IPMI, user id 2 is reserved for the 'ADMIN' username.
#   On ASUS IPMI, user id 2 is reserved for the 'admin' username.
# @param password
#   Controls the password of the user to be created.
#
define ipmi::user (
  String $user     = 'root',
  Integer $priv    = 4,
  Boolean $enable  = true,
  Integer $user_id = 3,
  Optional[Variant[Sensitive[String[1]], String[1]]] $password = undef,
) {
  require ipmi::install

  if $enable {
    if empty($password) {
      fail("You must supply a password to enable ${user} with ipmi::user")
    }

    case $priv {
      1: { $privilege = 'CALLBACK' }
      2: { $privilege = 'USER' }
      3: { $privilege = 'OPERATOR' }
      4: { $privilege = 'ADMINISTRATOR' }
      default: { fail('invalid privilege level specified') }
    }

    if $password =~ Sensitive {
      # unwrap before Puppet 6.24 can only be called on Sensitive values
      $real_password = $password.unwrap
    } else {
      $real_password = $password
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
      command => "/usr/bin/ipmitool user set password ${user_id} \'${real_password}\'",
      unless  => "/usr/bin/ipmitool user test ${user_id} 16 \'${real_password}\'",
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
  } else {
    exec { "ipmi_user_priv_${title}":
      command => "/usr/bin/ipmitool user priv ${user_id} 0xF 1",
      unless  => "/usr/bin/test \"$(ipmitool user list 1 | grep '^${user_id}' | awk '{print \$6}' | head -n1)\" = 'NO ACCESS'",
      notify  => [Exec["ipmi_user_disable_${title}"], Exec["ipmi_user_disable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
    }

    exec { "ipmi_user_disable_${title}":
      command     => "/usr/bin/ipmitool user disable ${user_id}",
      refreshonly => true,
    }

    exec { "ipmi_user_disable_sol_${title}":
      command     => "/usr/bin/ipmitool sol payload disable 1 ${user_id}",
      refreshonly => true,
    }

    exec { "ipmi_user_channel_setaccess_${title}":
      command     => "/usr/bin/ipmitool channel setaccess 1 ${user_id} callin=off ipmi=off link=off privilege=15",
      refreshonly => true,
    }
  }
}
