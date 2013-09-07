# == Class: ipmi
#
# === Examples
#
# include ipmi
#
# class { 'ipmi':
#   start_ipmievd => true,
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
  $start_ipmievd = false,
) inherits ipmi::params {
  class { 'ipmi::install': } ->
  class { 'ipmi::service':
    start_ipmievd => $start_ipmievd,
  } ->
  Class['Ipmi']
}
