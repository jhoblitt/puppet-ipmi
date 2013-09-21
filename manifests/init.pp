# == Class: ipmi
#
#
# === Parameters
#
# [*service_ensure*]
#
# String.  Possible values: 'running', 'stopped'
#
# Controls the state of the `ipmi` service.
#
# Default: 'running'
#
# [*ipmievd_service_ensure*]
#
# String.  Possible values: 'running', 'stopped'
#
# Controls the state of the `ipmievd` service.
#
# Default: 'stopped'
#
# === Examples
#
#
# include ipmi
#
# class { 'ipmi':
#   service_ensure         => 'running',
#   ipmievd_service_ensure => 'running',
# }
#
# === Authors
#
# Joshua Hoblitt <jhoblitt@cpan.org>
# Mike Arnold <mike@razorsedge.org>
#
# === Copyright
#
# Copyright (C) 2013 Joshua Hoblitt
# Copyright (C) 2013 Mike Arnold, unless otherwise noted.
#
class ipmi (
  $service_ensure         = 'running',
  $ipmievd_service_ensure = 'stopped',
) inherits ipmi::params {
  validate_re($service_ensure, '^running$|^stopped$')
  validate_re($ipmievd_service_ensure, '^running$|^stopped$')

  $enable_ipmi = $service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  $enable_ipmievd = $ipmievd_service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  class { 'ipmi::service::ipmi':
    ensure => $service_ensure,
    enable => $enable_ipmi,
  }

  class { 'ipmi::service::ipmievd':
    ensure => $ipmievd_service_ensure,
    enable => $enable_ipmievd,
  }

  class { 'ipmi::install': } ->
  Class['ipmi::service::ipmi'] ->
  Class['ipmi::service::ipmievd'] ->
  Class['ipmi']
}
