#
# @summary Write IPMI_WATCHDOG in the OpenIPMI daemon config
#
# Declared by ipmi::watchdog whenever the watchdog is managed: passed through
# when OpenIPMI owns /dev/watchdog, and as enable => false, only_if_exists =>
# true when systemd owns it. Setting IPMI_WATCHDOG=no never arms the BMC, so
# the systemd case only makes sure the OpenIPMI switch is off on any
# pre-existing, non-empty config; it never creates ipmi.conf and never writes
# a "yes" that would make the OpenIPMI service load the module on its own.
#
# The value is written on every run so that disabling the watchdog sets it
# back to "no" instead of leaving a stale "yes".
#
# @param enable
#   `true` writes `IPMI_WATCHDOG=yes`, `false` writes `no`.
# @param only_if_exists
#   Only apply the change if the config file already exists and is non-empty
#   (augments `onlyif` matches `size > 0`), rather than creating the file.
#
# @api private
#
class ipmi::watchdog::openipmi::watchdog_param (
  Boolean $enable,
  Boolean $only_if_exists = false,
) {
  assert_private()

  if $enable {
    $ipmi_watchdog = 'yes'
  } else {
    $ipmi_watchdog = 'no'
  }

  if $only_if_exists {
    $onlyif = "match /files${ipmi::config_file} size > 0"
  } else {
    $onlyif = undef
  }

  augeas { 'ipmi_watchdog':
    context => "/files${ipmi::config_file}",
    changes => [
      "set IPMI_WATCHDOG ${ipmi_watchdog}",
    ],
    onlyif  => $onlyif,
  }
}
