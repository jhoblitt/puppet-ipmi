#
# @summary Load the ipmi_watchdog kernel module, now and at boot
#
# Declared by ipmi::watchdog with `manage => true` only when systemd owns the
# device; under OpenIPMI the OpenIPMI service loads the module.
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
# @param options
#   Module options as `name=value` words separated by spaces. Without any, no
#   modprobe.d file is written.
#
# @api private
#
class ipmi::watchdog::kmod (
  Boolean $manage = false,
  Optional[String[1]] $options = undef,
) {
  assert_private()

  $modprobe_ensure = ($manage and $options =~ NotUndef) ? {
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
    content => "# Managed by Puppet (ipmi::watchdog)\noptions ipmi_watchdog ${options}\n",
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
      # /sys/module also exists for a driver built into the kernel, which
      # /proc/modules does not list.
      unless  => 'test -d /sys/module/ipmi_watchdog',
      path    => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      require => File['/etc/modprobe.d/50-ipmi-watchdog.conf'],
    }
  }
}
