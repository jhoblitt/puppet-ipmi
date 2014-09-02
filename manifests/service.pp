# == Class: ipmi::service
#
# This class should be considered private.
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
class ipmi::service (
  $start_ipmievd = false,
) {
  validate_bool($start_ipmievd)

  case $start_ipmievd {
    /(true)/: {
      $ipmievd_ensure = 'running'
      $ipmievd_enable = true
    }
    /(false)/: {
      $ipmievd_ensure = 'stopped'
      $ipmievd_enable = false
    }
    default: {
      fail('start_ipmievd parameter must be true or false')
    }
  }

  service{ 'ipmi':
    ensure     => running,
    hasstatus  => true,
    hasrestart => true,
    enable     => true,
  }

  service{ 'ipmievd':
    ensure     => $ipmievd_ensure,
    hasrestart => true,
    hasstatus  => true,
    enable     => $ipmievd_enable,
  }
}
