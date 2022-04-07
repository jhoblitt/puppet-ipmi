#
# @api private
#
class ipmi::service::ipmievd (
  Stdlib::Ensure::Service $ensure = 'running',
  Boolean $enable                 = true,
) {
  assert_private()

  service { 'ipmievd':
    ensure     => $ensure,
    hasstatus  => true,
    hasrestart => true,
    enable     => $enable,
  }
}
