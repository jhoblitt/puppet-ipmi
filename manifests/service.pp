# == Class: ipmi::service
#
# This class should be considered private.
#
class ipmi::service (
  $start_ipmievd = false,
) {
  validate_bool($start_ipmievd)

  case $start_ipmievd {
    /(true)/: {
      $ipmievd_ensure = 'running'
      $ipmievd_enable = true
    }
    /(false)/: {
      $ipmievd_ensure = 'stopped'
      $ipmievd_enable = false
    }
    default: {
      fail('start_ipmievd parameter must be true or false')
    }
  }

  service{ 'ipmi':
    ensure     => running,
    hasstatus  => true,
    hasrestart => true,
    enable     => true,
  }

  service{ 'ipmievd':
    ensure     => $ipmievd_ensure,
    hasrestart => true,
    hasstatus  => true,
    enable     => $ipmievd_enable,
  }
}
