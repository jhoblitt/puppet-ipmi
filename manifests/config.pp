#
# @api private
#
class ipmi::config {
  assert_private()

  $watchdog_real = $ipmi::watchdog ? {
    true    => 'yes',
    default => 'no',
  }

  augeas { $ipmi::params::config_location:
    context => "/files${ipmi::params::config_location}",
    changes => [
      "set IPMI_WATCHDOG ${watchdog_real}",
    ],
  }
}
