# == Class: ipmi::service::ipmi
#
# This class should be considered private.
#
class ipmi::service::ipmi (
  $ensure = 'running',
  $enable = true,
) {
  validate_re($ensure, '^running$|^stopped$')
  validate_bool($enable)

  service{ 'ipmi':
    ensure     => $ensure,
    hasstatus  => true,
    hasrestart => true,
    enable     => $enable,
  }

}
