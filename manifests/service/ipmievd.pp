# == Class: ipmi::service::ipmievd
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
class ipmi::service::ipmievd (
  $ensure = 'running',
  $enable = true,
) {
  validate_re($ensure, '^running$|^stopped$')
  validate_bool($enable)

  service{ 'ipmievd':
    ensure      => $ensure,
    hasstatus   => true,
    hasrestart  => true,
    enable      => $enable,
  }

}
