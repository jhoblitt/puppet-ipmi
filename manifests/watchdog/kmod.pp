#
# @summary Load the ipmi_watchdog kernel module, now and at boot
#
# Writes the module's options to modprobe.d, lists it in modules-load.d and
# loads it now. Loading the module creates /dev/watchdog but does not start
# the BMC timer. Options only take effect the next time the module is loaded,
# so changing them on a host where it is already loaded needs a reboot or a
# manual reload.
#
# The files are declared even when the module is not managed, so that turning
# it off removes them. Puppet never unloads the module: unloading it does not
# stop a running BMC timer, which then resets the host because nothing can
# ping it any more.
#
# @param manage
#   Whether the files are present and the module is loaded.
# @param timeout
#   Watchdog timeout in seconds, passed as the `timeout` module option.
#   `0` writes no option, leaving the driver default (10 seconds).
# @param options
#   Extra module options. A `timeout` key here must not disagree with
#   `timeout` above; a mismatch fails the catalog.
#
# @api private
#
class ipmi::watchdog::kmod (
  Boolean $manage = false,
  Integer[0] $timeout = 0,
  Hash[String[1], Scalar] $options = {},
) {
  assert_private()

  if $manage and $timeout > 0 and 'timeout' in $options and String($options['timeout']) != String($timeout) {
    fail("ipmi::watchdog_module_options timeout (${options['timeout']}) conflicts with ipmi::watchdog_timeout (${timeout}); set only one")
  }

  if $timeout > 0 {
    $timeout_options = { 'timeout' => $timeout }
  } else {
    $timeout_options = {}
  }

  $settings = $timeout_options + $options
  $option_words = $settings.map |$option, $value| { "${option}=${value}" }

  $modprobe_ensure = ($manage and !$settings.empty) ? {
    true    => 'file',
    default => 'absent',
  }
  $modules_load_ensure = $manage ? {
    true    => 'file',
    default => 'absent',
  }

  file { '/etc/modprobe.d/50-ipmi-watchdog.conf':
    ensure  => $modprobe_ensure,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet (ipmi::watchdog)\noptions ipmi_watchdog ${option_words.join(' ')}\n",
  }

  file { '/etc/modules-load.d/50-ipmi-watchdog.conf':
    ensure  => $modules_load_ensure,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet (ipmi::watchdog)\nipmi_watchdog\n",
  }

  if $manage {
    exec { 'ipmi::watchdog modprobe ipmi_watchdog':
      command => 'modprobe ipmi_watchdog',
      unless  => "grep -q '^ipmi_watchdog ' /proc/modules",
      path    => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      require => File['/etc/modprobe.d/50-ipmi-watchdog.conf'],
    }
  }
}
