#
# @api private
#
class ipmi::service::ipmi (
  Boolean $service_manage         = true,
  Stdlib::Ensure::Service $ensure = 'running',
  Boolean $enable                 = true,
  String $ipmi_service_name       = 'ipmi',
) {
  assert_private()

  if $service_manage {
    service { $ipmi_service_name:
      ensure => $ensure,
      enable => $enable,
    }
  }
}
