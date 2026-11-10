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
# @param channel
#   Controls the channel of the IPMI user to be configured.
#   Defaults to the first detected lan channel, starting at 1 ending at 11
# @param purge_id_mismatch
#   When true, any IPMI user slot that holds $user at an ID other than $user_id
#   will be blanked and disabled before the desired slot is configured.
#   IPMI slots cannot be deleted; clearing the name and disabling access is the
#   BMC-standard equivalent. Defaults to false. Only applies when $enable is true.
#
define ipmi::user (
  String $user                                                 = 'root',
  Integer $priv                                                = 4,
  Boolean $enable                                              = true,
  Integer $user_id                                             = 3,
  Optional[Variant[Sensitive[String[1]], String[1]]] $password = undef,
  Optional[Integer] $channel                                   = undef,
  Boolean $purge_id_mismatch                                   = false,
) {
  require ipmi::install

  $_real_channel = $channel ? {
    undef => $ipmi::default_channel,
    default => $channel,
  }

  # Blank any IPMI user slot holding $user at an ID other than $user_id.
  # Must run before ipmi_user_add_${title} to avoid duplicate-name conflicts on the BMC.
  # Not applied when $enable is false: disabling operates on $user_id directly
  # and a mismatch at another slot is harmless in that case.
  if $purge_id_mismatch and $enable {
    file { '/usr/libexec/puppet_ipmi_purge_id_mismatch':
      ensure => 'file',
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
      source => 'puppet:///modules/ipmi/puppet_ipmi_purge_id_mismatch',
    }

    exec { "ipmi_user_purge_mismatch_${title}":
      command => "/usr/libexec/puppet_ipmi_purge_id_mismatch ${_real_channel} ${user} ${user_id}",
      onlyif  => "/usr/libexec/puppet_ipmi_purge_id_mismatch --onlyif ${_real_channel} ${user} ${user_id}",
      before  => Exec["ipmi_user_add_${title}"],
      require => File['/usr/libexec/puppet_ipmi_purge_id_mismatch'],
    }
  }

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
      unless  => "/usr/bin/ipmitool user list ${_real_channel} | grep -qE '^${user_id}[ ]+${user} '",
      notify  => [Exec["ipmi_user_priv_${title}"], Exec["ipmi_user_setpw_${title}"]],
    }

    exec { "ipmi_user_priv_${title}":
      command => "/usr/bin/ipmitool user priv ${user_id} ${priv} ${_real_channel}",
      unless  => "/usr/bin/ipmitool user list ${_real_channel} | grep -qE '^${user_id} .+ ${privilege}$'",
      notify  => [Exec["ipmi_user_enable_${title}"], Exec["ipmi_user_enable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
    }

    if $real_password.length > 20 {
      fail('ipmi v2 restricts passwords to 20 or fewer characters')
    }
    # Password capacity parameter defaults to 16 if not provided
    #  and will result in truncated passwords
    if $real_password.length <= 16 {
      $password_capacity = '16'
    } else {
      $password_capacity = '20'
    }

    $unless_cmd = @("CMD"/L$)
      /usr/bin/ipmitool user test ${user_id} 16 "\$PASSWORD" || \
      /usr/bin/ipmitool user test ${user_id} 20 "\$PASSWORD"
      |- CMD
    exec { "ipmi_user_setpw_${title}":
      environment => ["PASSWORD=${real_password}"],
      command     => "/usr/bin/ipmitool user set password ${user_id} \"\$PASSWORD\" ${password_capacity}",
      unless      => $unless_cmd,
      notify      => Exec[
        "ipmi_user_enable_${title}",
        "ipmi_user_enable_sol_${title}",
        "ipmi_user_channel_setaccess_${title}"
      ],
    }

    exec { "ipmi_user_enable_sol_${title}":
      command     => "/usr/bin/ipmitool sol payload enable ${_real_channel} ${user_id}",
      refreshonly => true,
    }

    exec { "ipmi_user_channel_setaccess_${title}":
      command     => "/usr/bin/ipmitool channel setaccess ${_real_channel} ${user_id} callin=on ipmi=on link=on privilege=${priv}",
      refreshonly => true,
    }
  } else {
    exec { "ipmi_user_priv_${title}":
      command => "/usr/bin/ipmitool user priv ${user_id} 0xF ${_real_channel}",
      unless  => "/usr/bin/ipmitool user list ${_real_channel} | grep -qE '^${user_id} .+ NO ACCESS$'",
      notify  => [Exec["ipmi_user_disable_${title}"], Exec["ipmi_user_disable_sol_${title}"], Exec["ipmi_user_channel_setaccess_${title}"]],
    }

    exec { "ipmi_user_disable_${title}":
      command     => "/usr/bin/ipmitool user disable ${user_id}",
      refreshonly => true,
    }

    exec { "ipmi_user_disable_sol_${title}":
      command     => "/usr/bin/ipmitool sol payload disable ${_real_channel} ${user_id}",
      refreshonly => true,
    }

    exec { "ipmi_user_channel_setaccess_${title}":
      command     => "/usr/bin/ipmitool channel setaccess ${_real_channel} ${user_id} callin=off ipmi=off link=off privilege=15",
      refreshonly => true,
    }
  }
}
