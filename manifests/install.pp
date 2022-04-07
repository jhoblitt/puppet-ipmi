#
# @api private
#
class ipmi::install {
  assert_private()

  package { $ipmi::params::ipmi_package:
    ensure => present,
  }
}
