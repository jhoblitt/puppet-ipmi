#
# @summary Manages OpenIPMI
#
# @param service_ensure
#   Controls the state of the `ipmi` service. Possible values: `running`, `stopped`
# @param ipmievd_service_ensure
#   Controls the state of the `ipmievd` service. Possible values: `running`, `stopped`
# @param watchdog
#   Controls whether the IPMI watchdog is enabled.
# @param snmps
#   `ipmi::snmp` resources to create.
# @param users
#   `ipmi::user` resources to create.
# @param networks
#   `ipmi::network` resources to create.
#
class ipmi (
  Stdlib::Ensure::Service $service_ensure         = 'running',
  Stdlib::Ensure::Service $ipmievd_service_ensure = 'stopped',
  Boolean $watchdog                               = false,
  Hash $snmps                                     = {},
  Hash $users                                     = {},
  Hash $networks                                  = {},
) inherits ipmi::params {
  $enable_ipmi = $service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  $enable_ipmievd = $ipmievd_service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  contain ipmi::install
  contain ipmi::config

  class { 'ipmi::service::ipmi':
    ensure            => $service_ensure,
    enable            => $enable_ipmi,
    ipmi_service_name => $ipmi::params::ipmi_service_name,
  }

  class { 'ipmi::service::ipmievd':
    ensure => $ipmievd_service_ensure,
    enable => $enable_ipmievd,
  }

  Class['ipmi::install']
  ~> Class['ipmi::config']
  ~> Class['ipmi::service::ipmi']
  ~> Class['ipmi::service::ipmievd']

  if $snmps {
    create_resources('ipmi::snmp', $snmps)
  }

  if $users {
    create_resources('ipmi::user', $users)
  }

  if $networks {
    create_resources('ipmi::network', $networks)
  }
}
