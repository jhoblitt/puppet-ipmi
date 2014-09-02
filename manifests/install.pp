# == Class: ipmi::install
#
# This class should be considered private.
#
class ipmi::install {
  package { $ipmi::params::ipmi_package:
    ensure => present,
  }
}
