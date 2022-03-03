# == Class: ipmi::params
#
# This class should be considered private.
#
class ipmi::params {
  case $::osfamily {
    'redhat': {
      case $::operatingsystemmajrelease {
        '5': {
          $ipmi_package = ['OpenIPMI', 'OpenIPMI-tools']
          $config_location = '/etc/sysconfig/ipmi'
          $ipmi_service_name = 'ipmi'
        }
        '6', '7', '8': {
          $ipmi_package = ['OpenIPMI', 'ipmitool']
          $config_location = '/etc/sysconfig/ipmi'
          $ipmi_service_name = 'ipmi'
        }
        default: {
          fail("Module ${module_name} is not supported on operatingsystemmajrelease ${::operatingsystemmajrelease}")
        }
      }
    }
    'debian': {
      case $::operatingsystem {
        'ubuntu': {
          $ipmi_package    = ['openipmi', 'ipmitool']
          $config_location = '/etc/default/openipmi'
          $ipmi_service_name = 'openipmi'
        }
        'debian': {
          $ipmi_package    = ['openipmi', 'ipmitool']
          $config_location = '/etc/default/openipmi'
          $ipmi_service_name = 'openipmi'
        }
        default: {
          fail("Module ${module_name} is not supported on operatingsystem ${::operatingsystem}")
        }
      }
    }
    default: {
      fail("Module ${module_name} is not supported on ${::operatingsystem}")
    }
  }

}
