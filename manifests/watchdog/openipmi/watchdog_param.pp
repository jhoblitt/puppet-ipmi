#
# @summary Write IPMI_WATCHDOG in the OpenIPMI service config
#
# This is the only place that touches IPMI_WATCHDOG. ipmi_watchdog is a
# single-open device: a second process that opens /dev/watchdog gets EBUSY,
# and whoever holds it controls the BMC timer, so exactly one component
# should own it. IPMI_WATCHDOG=yes makes the OpenIPMI service load the module
# (with IPMI_WATCHDOG_OPTIONS); the service does not hold the device open
# itself.
#
# The value is written on every run so that disabling the watchdog sets it
# back to "no" instead of leaving a stale "yes".
#
# @param enable
#   `true` writes `IPMI_WATCHDOG=yes`, `false` writes `no`.
#
# @api private
#
class ipmi::watchdog::openipmi::watchdog_param (
  Boolean $enable,
) {
  assert_private()

  if $enable {
    $ipmi_watchdog = 'yes'
  } else {
    $ipmi_watchdog = 'no'
  }

  augeas { 'ipmi_watchdog':
    context => "/files${ipmi::config_file}",
    changes => [
      "set IPMI_WATCHDOG ${ipmi_watchdog}",
    ],
  }
}
