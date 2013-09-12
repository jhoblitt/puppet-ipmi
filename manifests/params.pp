# == Class: ipmi::params
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
class ipmi::params {
  case $::osfamily {
    'redhat': {
      case $::operatingsystemmajrelease {
        5: {
          # el5.x
          $ipmi_package = ['OpenIPMI', 'OpenIPMI-tools']
        }
        6: {
          # el6.x
          $ipmi_package = ['OpenIPMI', 'ipmitool']
        }
        default: {
          fail("Module ${module_name} is not supported on operatingsystemmajrelease ${::operatingsystemmajrelease}")
        }
      }
    }
    default: {
      fail("Module ${module_name} is not supported on ${::operatingsystem}")
    }
  }

}
