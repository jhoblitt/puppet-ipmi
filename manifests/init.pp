# == Class: ipmi
#
# Please refer to https://github.com/jhoblitt/puppet-ipmi#usage for
# parameter documentation.
#
class ipmi (
  $service_ensure         = 'running',
  $ipmievd_service_ensure = 'stopped',
  $watchdog               = false,
) inherits ipmi::params {
  validate_re($service_ensure, '^running$|^stopped$')
  validate_re($ipmievd_service_ensure, '^running$|^stopped$')
  validate_bool($watchdog)

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

  class { 'ipmi::service::ipmi':
    ensure => $service_ensure,
    enable => $enable_ipmi,
  }

  class { 'ipmi::service::ipmievd':
    ensure => $ipmievd_service_ensure,
    enable => $enable_ipmievd,
  }

  anchor { 'ipmi::begin': }
  anchor { 'ipmi::end': }

  Anchor['ipmi::begin'] -> Class['::ipmi::install'] ~> Class['::ipmi::config']
    ~> Class['::ipmi::service::ipmi'] ~> Class['::ipmi::service::ipmievd']
    -> Anchor['ipmi::end']
}
