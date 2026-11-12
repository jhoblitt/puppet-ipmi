#
# @summary Have the OpenIPMI service load ipmi_watchdog
#
# Declared by ipmi::watchdog when OpenIPMI is the chosen owner of the
# watchdog. IPMI_WATCHDOG=yes makes the OpenIPMI service load the
# ipmi_watchdog kernel module (with IPMI_WATCHDOG_OPTIONS) when it starts.
# The service does not open or ping /dev/watchdog itself, so this class does
# not start the BMC timer; that is left to whatever opens the device.
#
# See ipmi::watchdog::openipmi::watchdog_param for why only one component
# may own the watchdog. Any other OpenIPMI service watchdog setting belongs
# here, next to the IPMI_WATCHDOG switch, so it is only applied when OpenIPMI
# is the chosen owner.
#
# @param enable
#   `true` sets IPMI_WATCHDOG to `yes`, `false` sets it to `no`.
# @param options
#   Module options for IPMI_WATCHDOG_OPTIONS, as `name=value` words separated
#   by spaces. Without any, IPMI_WATCHDOG_OPTIONS is left as it is.
#
# @api private
#
class ipmi::watchdog::openipmi (
  Boolean $enable,
  Optional[String[1]] $options = undef,
) {
  assert_private()

  class { 'ipmi::watchdog::openipmi::watchdog_param':
    enable  => $enable,
    options => $options,
  }

  contain ipmi::watchdog::openipmi::watchdog_param
}
