# == Class: ipmi
#
# Please refer to https://github.com/jhoblitt/puppet-ipmi#usage for
# parameter documentation.
#
class ipmi (
  $service_ensure         = 'running',
  $ipmievd_service_ensure = 'stopped',
  $watchdog               = false,
  $snmps                  = {},
  $users                  = {},
  $networks               = {},
) inherits ipmi::params {
  validate_re($service_ensure, '^running$|^stopped$')
  validate_re($ipmievd_service_ensure, '^running$|^stopped$')
  validate_bool($watchdog)

  validate_hash($snmps)
  validate_hash($users)
  validate_hash($networks)

  $enable_ipmi = $service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  $enable_ipmievd = $ipmievd_service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  include ::ipmi::install
  include ::ipmi::config

  if ( (($::osfamily == 'Debian') and ($::operatingsystemmajrelease > 8)) or
       (($::osfamily == 'RedHat') and ($::operatingsystemmajrelease > 6))
     ){
    class { '::ipmi::service::ipmi':
      ensure            => $service_ensure,
      enable            => $enable_ipmi,
      ipmi_service_name => $ipmi::params::ipmi_service_name,
      notify            => Class['::ipmi::service::ipmievd'],
      subscribe         => Class['::ipmi::']
    }
  }

  class { '::ipmi::service::ipmievd':
    ensure => $ipmievd_service_ensure,
    enable => $enable_ipmievd,
  }

  anchor { 'ipmi::begin': }
  anchor { 'ipmi::end': }

  Anchor['ipmi::begin'] -> Class['::ipmi::install'] ~> Class['::ipmi::config']
    ~> Class['::ipmi::service::ipmievd']
    -> Anchor['ipmi::end']



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
