# @summary systemd-system.conf(5) [Manager] settings for the watchdog drop-in
#
# Each key is written as one `Key=value` line, so a value may not span lines.
type Ipmi::Watchdog::SystemdOptions = Hash[
  Pattern[/\A[A-Z][A-Za-z]*\z/],
  Variant[Integer, Pattern[/\A[^\n]*\z/]],
]
