# == Class: ipmi::service::ipmievd
#
# This class should be considered private.
#
class ipmi::service::ipmievd (
  $ensure = 'running',
  $enable = true,
) {
  validate_re($ensure, '^running$|^stopped$')
  validate_bool($enable)

  service{ 'ipmievd':
    ensure     => $ensure,
    hasstatus  => true,
    hasrestart => true,
    enable     => $enable,
  }

}
