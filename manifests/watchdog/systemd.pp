#
# @summary Let systemd (PID 1) own /dev/watchdog
#
# The device can only be opened once, so ipmi::watchdog also forces the
# OpenIPMI service's IPMI_WATCHDOG to "no" when systemd is the owner.
#
# Writes a system.conf [Manager] drop-in and re-executes PID 1 when it
# changes, which is when systemd re-reads system.conf. RuntimeWatchdogSec is
# always written, and `0` means off: no watchdog device is opened, configured
# or pinged. This lets a host with a buggy BMC watchdog keep
# `watchdog => true` (module loaded) while systemd leaves the device alone.
#
# WatchdogDevice is not written unless set in `options`. systemd tries
# /dev/watchdog0 first and, from 252, falls back to /dev/watchdog. On a host
# with another watchdog driver loaded, such as iTCO_wdt, /dev/watchdog0 may
# not be the BMC, so set `WatchdogDevice` in `options`.
#
# The drop-in is declared even when systemd is not the owner, so that
# switching the owner or turning the watchdog off removes it.
#
# @param enable
#   Whether the drop-in is present. When `false` it is removed.
# @param timeout
#   Seconds, written as RuntimeWatchdogSec. `0` is off.
# @param options
#   Extra [Manager] settings. A `RuntimeWatchdogSec` here replaces `timeout`.
#
# @api private
#
class ipmi::watchdog::systemd (
  Boolean $enable,
  Integer[0] $timeout = 0,
  Ipmi::Watchdog::SystemdOptions $options = {},
) {
  assert_private()

  $dropin = '/etc/systemd/system.conf.d/50-ipmi-watchdog.conf'
  $settings = { 'RuntimeWatchdogSec' => $timeout } + $options
  $lines = $settings.map |$key, $value| { "${key}=${value}\n" }

  if $enable {
    $ensure = 'file'

    # The parameters puppet/systemd's systemd::system::dropin_file uses by
    # default, so either module may declare the directory first.
    $dropin_dir = {
      ensure                  => 'directory',
      owner                   => 'root',
      group                   => 'root',
      mode                    => '0755',
      recurse                 => false,
      purge                   => false,
      selinux_ignore_defaults => false,
    }
    ensure_resource('file', '/etc/systemd/system.conf.d', $dropin_dir)
  } else {
    $ensure = 'absent'
  }

  file { $dropin:
    ensure  => $ensure,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet (ipmi::watchdog)\n[Manager]\n${lines.join('')}",
  }

  exec { 'ipmi::watchdog systemctl daemon-reexec':
    command     => 'systemctl daemon-reexec',
    path        => ['/usr/bin', '/bin'],
    refreshonly => true,
    subscribe   => File[$dropin],
  }
}
