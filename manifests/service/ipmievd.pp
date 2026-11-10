#
# @api private
#
class ipmi::service::ipmievd (
  Stdlib::Ensure::Service $ensure = 'running',
  Boolean $enable                 = true,
  String $service_name            = 'ipmievd',
) {
  assert_private()

  service { $service_name:
    ensure => $ensure,
    enable => $enable,
  }
}
