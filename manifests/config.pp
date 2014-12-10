# == Class: ipmi::config
#
# This class should be considered private.
#
class ipmi::config {

  $watchdog_real = $::ipmi::watchdog ? {
    true    => 'yes',
    default => 'no',
  }

  augeas { '/etc/sysconfig/ipmi':
    context => '/files/etc/sysconfig/ipmi',
    changes => [
      "set IPMI_WATCHDOG ${watchdog_real}",
    ],
  }
}
