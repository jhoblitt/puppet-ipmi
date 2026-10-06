#
# @summary Manages OpenIPMI
#
# @param packages
#   List of packages to install.
# @param config_file
#   Absolute path to the ipmi service config file.
# @param service_name
#   Name of IPMI service.
# @param service_ensure
#   Controls the state of the `ipmi` service. Possible values: `running`, `stopped`
# @param ipmievd_service_name
#   Name of ipmievd service.
# @param ipmievd_service_ensure
#   Controls the state of the `ipmievd` service. Possible values: `running`, `stopped`
# @param watchdog
#   Controls whether the IPMI watchdog is enabled.
# @param snmps
#   `ipmi_snmp` resources to create.
# @param users
#   `ipmi_user` resources to create.
# @param networks
#   `ipmi_network` resources to create.
# @param service_manage
#   Controls whether the `ipmi` service is managed. When `false`, the
#   `service` resource is not declared and the service is left unmanaged
#   (handled by the administrator or an external tooling system).
# @param default_channel
#   Optional default IPMI channel (1-15) to use for resources that do not
#   specify one. When unset, class-declared resources use the node's
#   ipmi.default.channel fact if valid; otherwise the class uses an integer
#   LAN title or channel 1. Directly declared native resources
#   do not use facts for their defaults.
#
class ipmi (
  Array[String] $packages,
  Stdlib::Absolutepath $config_file,
  String $service_name,
  String $ipmievd_service_name,
  Variant[Stdlib::Ensure::Service, String[0]] $service_ensure,
  Stdlib::Ensure::Service $ipmievd_service_ensure,
  Boolean $watchdog,
  Optional[Hash] $snmps,
  Optional[Hash] $users,
  Optional[Hash] $networks,
  Boolean $service_manage = true,
  Optional[Integer[1, 15]] $default_channel = undef,
) {
  contain ipmi::install
  contain ipmi::config
  contain ipmi::service

  Class['ipmi::install']
  ~> Class['ipmi::config']
  ~> Class['ipmi::service']

  # The class sees the target node's facts on Puppet Server. Native type
  # default to blocks run on the compiler and must not read local Facter data.
  $fact_channel = $facts.dig('ipmi', 'default', 'channel')
  if $default_channel != undef {
    $effective_channel = $default_channel
  } elsif $fact_channel =~ Integer[1, 15] {
    $effective_channel = $fact_channel
  } else {
    $effective_channel = 1
  }

  $user_defaults = { 'channel' => $effective_channel }
  $lan_defaults = { 'lan_channel' => $effective_channel }

  if $snmps {
    $snmps.each |$key, $params| {
      $title = String($key)
      if $default_channel == undef and $title =~ /\A[0-9]+\z/ {
        $snmp_defaults = { 'lan_channel' => Integer($title, 10) }
      } else {
        $snmp_defaults = $lan_defaults
      }
      ipmi_snmp { $title:
        * => $snmp_defaults + $params,
      }
      Class['ipmi::install'] -> Ipmi_snmp[$title]
    }
  }

  if $users {
    $users.each |$key, $params| {
      $title = String($key)
      ipmi_user { $title:
        * => $user_defaults + $params,
      }
      Class['ipmi::install'] -> Ipmi_user[$title]
    }
  }

  if $networks {
    $networks.each |$key, $params| {
      $title = String($key)
      if $default_channel == undef and $title =~ /\A[0-9]+\z/ {
        $network_defaults = { 'lan_channel' => Integer($title, 10) }
      } else {
        $network_defaults = $lan_defaults
      }
      ipmi_network { $title:
        * => $network_defaults + $params,
      }
      Class['ipmi::install'] -> Ipmi_network[$title]
    }
  }
}
