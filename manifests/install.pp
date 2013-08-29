# == Class: ipmi::install
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
class ipmi::install {
  case $::lsbmajdistrelease {
    5: {
      $ipmi_package = ['OpenIPMI', 'OpenIPMI-tools']
    }
    default: {
      # el6.x
      $ipmi_package = ['OpenIPMI', 'ipmitool']
    }
  }

  package { $ipmi_package:
    ensure => present,
  }
}
