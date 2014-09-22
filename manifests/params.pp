# == Class: ipmi::params
#
# This class should be considered private.
#
class ipmi::params {
  case $::osfamily {
    'redhat': {
      case $::operatingsystemmajrelease {
        5: {
          # el5.x
          $ipmi_package = ['OpenIPMI', 'OpenIPMI-tools']
        }
        6, 7: {
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
