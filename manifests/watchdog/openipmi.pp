#
# @summary Write IPMI_WATCHDOG in the OpenIPMI service config
#
# Declared by ipmi::watchdog whenever the watchdog is managed. When OpenIPMI
# owns /dev/watchdog, IPMI_WATCHDOG=yes makes the OpenIPMI service load the
# ipmi_watchdog kernel module (with IPMI_WATCHDOG_OPTIONS) when it starts.
# The service does not open or ping /dev/watchdog itself, so this does not
# start the BMC timer; that is left to whatever opens the device.
#
# When systemd owns it, the class is declared with enable => false and
# only_if_exists => true. Setting IPMI_WATCHDOG=no never arms the BMC, so
# this only makes sure the OpenIPMI switch is off on any pre-existing,
# non-empty config; it never creates the config file and never writes a
# "yes" that would make the OpenIPMI service load the module on its own.
#
# The value is written on every run so that disabling the watchdog sets it
# back to "no" instead of leaving a stale "yes".
#
# @param enable
#   `true` writes `IPMI_WATCHDOG=yes`, `false` writes `no`.
# @param only_if_exists
#   Only apply the change if the config file already exists and is non-empty
#   (augments `onlyif` matches `size > 0`), rather than creating the file.
# @param options
#   Module options for IPMI_WATCHDOG_OPTIONS, as `name=value` words separated
#   by spaces, written only with `enable`, as the service reads them only
#   then. Without any, the package's value, such as `timeout=60`, stays in
#   place.
#
# @api private
#
class ipmi::watchdog::openipmi (
  Boolean $enable,
  Boolean $only_if_exists = false,
  Optional[String[1]] $options = undef,
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

  if $enable and $options =~ NotUndef {
    $options_changes = ["set IPMI_WATCHDOG_OPTIONS '\"${options}\"'"]
  } else {
    $options_changes = []
  }

  augeas { 'ipmi_watchdog':
    context => "/files${ipmi::config_file}",
    changes => ["set IPMI_WATCHDOG ${ipmi_watchdog}"] + $options_changes,
    onlyif  => $onlyif,
  }
}
