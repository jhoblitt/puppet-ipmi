#
# @summary Let systemd (PID 1) own /dev/watchdog
#
# The device can only be opened once, so ipmi::watchdog also forces the
# OpenIPMI service's IPMI_WATCHDOG to "no" when systemd is the owner.
#
# Writes a system.conf [Manager] drop-in and re-executes PID 1 when it
# changes, which is when systemd re-reads system.conf. RuntimeWatchdogSec is
# written only for a non-zero `timeout` or when set in `options`: an explicit
# `0` would override a RuntimeWatchdogSec set in system.conf or an earlier
# drop-in. Without any setting to write, the drop-in is removed.
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
#   Whether the drop-in may be present. When `false` it is removed.
# @param timeout
#   Seconds, written as RuntimeWatchdogSec. `0` writes nothing.
# @param options
#   Extra [Manager] settings. A `RuntimeWatchdogSec` here replaces `timeout`;
#   `0` turns systemd's runtime watchdog off.
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

  if $timeout > 0 {
    $timeout_settings = { 'RuntimeWatchdogSec' => $timeout }
  } else {
    $timeout_settings = {}
  }

  $settings = $timeout_settings + $options
  $lines = $settings.map |$key, $value| { "${key}=${value}\n" }

  if $enable and !$settings.empty {
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
