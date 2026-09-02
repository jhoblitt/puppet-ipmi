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
#   The user id of the user to be created, or 'auto' to let the provider
#   select one. Should be unique from existing users.
#
#   When set to 'auto', the provider first checks for an existing user with
#   the requested username and reuses that ID.  Otherwise it selects the
#   lowest unused ID reported by the BMC.  ID 1 is the anonymous slot and is
#   never returned by 'auto'.
#
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
  Variant[Integer, Enum['auto']] $user_id                      = 3,
  Optional[Variant[Sensitive[String[1]], String[1]]] $password = undef,
  Optional[Integer] $channel                                   = undef,
  Boolean $purge_id_mismatch                                   = false,
) {
  require ipmi::install

  $_real_channel = $channel ? {
    undef   => $ipmi::default_channel,
    default => $channel,
  }

  $_enable = $enable ? {
    true    => true,
    default => false,
  }

  $_purge = $purge_id_mismatch ? {
    true    => true,
    default => false,
  }

  if $enable {
    if empty($password) {
      fail("You must supply a password to enable ${user} with ipmi::user")
    }

    unless $priv in [1, 2, 3, 4] {
      fail("priv must be 1 (CALLBACK), 2 (USER), 3 (OPERATOR), or 4 (ADMINISTRATOR), got ${priv}")
    }
  }

  ipmi_user { "ipmi_user_${title}":
    user              => $user,
    user_id           => $user_id,
    password          => $password,
    priv              => $priv,
    channel           => $_real_channel,
    enable            => $_enable,
    purge_id_mismatch => $_purge,
  }
}
