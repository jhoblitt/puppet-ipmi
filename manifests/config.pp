#
# @api private
#
class ipmi::config {
  assert_private()

  $watchdog_real = $ipmi::watchdog ? {
    true    => 'yes',
    default => 'no',
  }

  augeas { $ipmi::config_file:
    context => "/files${ipmi::config_file}",
    changes => [
      "set IPMI_WATCHDOG ${watchdog_real}",
    ],
  }
}
