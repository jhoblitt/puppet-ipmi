#
# @api private
#
class ipmi::service::ipmi (
  Stdlib::Ensure::Service $ensure = 'running',
  Boolean $enable                 = true,
  String $ipmi_service_name       = 'ipmi',
) {
  assert_private()

  service { $ipmi_service_name:
    ensure => $ensure,
    enable => $enable,
  }
}
