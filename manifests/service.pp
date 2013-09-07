# == Class: ipmi::service
#
# This class should be considered private.
#
# === Authors
#
# Joshua Hoblitt <jhoblitt@cpan.org>
#
# === Copyright
#
# Copyright (C) 2013 Joshua Hoblitt
#
class ipmi::service {
  service{ 'ipmi':
    ensure      => running,
    hasstatus   => true,
    hasrestart  => true,
    enable      => true,
  }

  service{ 'ipmievd':
    ensure      => running,
    hasrestart  => true,
    hasstatus   => true,
    enable      => true,
  }
}
