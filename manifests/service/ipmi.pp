# == Class: ipmi::service::ipmi
#
# This class should be considered private.
#
class ipmi::service::ipmi (
  $ensure = 'running',
  $enable = true,
  $ipmi_service_name = 'ipmi',
) {
  validate_re($ensure, '^running$|^stopped$')
  validate_bool($enable)

  service{ $ipmi_service_name:
    ensure     => $ensure,
    hasstatus  => true,
    hasrestart => true,
    enable     => $enable,
  }

}
