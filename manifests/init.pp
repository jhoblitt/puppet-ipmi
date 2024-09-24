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
#   `ipmi::snmp` resources to create.
# @param users
#   `ipmi::user` resources to create.
# @param networks
#   `ipmi::network` resources to create.
# @param default_channel
#   Default channel to use for IPMI commands.
#
class ipmi (
  Array[String] $packages,
  Stdlib::Absolutepath $config_file,
  String $service_name,
  Stdlib::Ensure::Service $service_ensure,
  String $ipmievd_service_name,
  Stdlib::Ensure::Service $ipmievd_service_ensure,
  Boolean $watchdog,
  Optional[Hash] $snmps,
  Optional[Hash] $users,
  Optional[Hash] $networks,
  Integer[0] $default_channel = Integer(fact('ipmi.default.channel') or 1),
) {
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
    ipmi_service_name => $service_name,
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
