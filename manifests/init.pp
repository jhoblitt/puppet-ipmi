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
  String $ipmievd_service_name,
  Variant[Stdlib::Ensure::Service, String[0]] $service_ensure,
  Stdlib::Ensure::Service $ipmievd_service_ensure,
  Boolean $watchdog,
  Optional[Hash] $snmps,
  Optional[Hash] $users,
  Optional[Hash] $networks,
  Integer[0] $default_channel = Integer(fact('ipmi.default.channel') or 1),
) {
  contain ipmi::install
  contain ipmi::config
  contain ipmi::service

  Class['ipmi::install']
  ~> Class['ipmi::config']
  ~> Class['ipmi::service']

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
