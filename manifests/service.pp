#
# @api private
#
class ipmi::service {
  assert_private()

  include ipmi

  $real_service_ensure = $ipmi::service_ensure ? {
    'running' => 'running',
    default   => 'stopped',
  }

  $enable_ipmi = $real_service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  $enable_ipmievd = $ipmi::ipmievd_service_ensure ? {
    'running' => true,
    'stopped' => false,
  }

  class { 'ipmi::service::ipmi':
    ensure            => $real_service_ensure,
    enable            => $enable_ipmi,
    ipmi_service_name => $ipmi::service_name,
  }

  class { 'ipmi::service::ipmievd':
    ensure       => $ipmi::ipmievd_service_ensure,
    enable       => $enable_ipmievd,
    service_name => $ipmi::ipmievd_service_name,
  }

  contain ipmi::service::ipmi
  contain ipmi::service::ipmievd
}
